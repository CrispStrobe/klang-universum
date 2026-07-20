// The caller side of the audio→tab contract (CrispASR §GT1,
// docs/music-transcription/GUITAR_TAB_SPEC.md → docs/TAB_ARRANGER_NEURAL_HANDOFF
// .md §audio): CrispASR ships a GP-FX-augmented TabCNN that emits, per
// frame, a 6×21 grid of LOG-probabilities and does NO decoding. WE own the DP.
//
// TabCNN's layer is six independent per-string softmaxes with no inter-string
// coupling, no temporal model, no decode — the published metrics are a plain
// per-frame argmax. A constrained Viterbi over the same layer is therefore a
// strict improvement, not a lossy adaptation: [decodeTabEmissions] runs a
// per-string temporal Viterbi that keeps each string on a stable fret (kills the
// single-frame flips argmax follows), while the string×class shape gives the
// hard structure — one note per string, fret in range — for free.
//
// Pure Dart (no Flutter, no model) → the decoder is unit-testable with synthetic
// emissions today, so the CrispASR TabCNN port has a green target before any
// weights exist. Mirrors how f0_viterbi decodes the CREPE/RMVPE pitch lattice.

import 'dart:typed_data';

import 'package:comet_beat/features/games/composition/tab_arranger.dart'
    show Fretting;

/// A standard guitar has six strings.
const int kTabStrings = 6;

/// TabCNN emits 21 classes per string: class 0 = the string is silent
/// ("closed"/not played), class `k ≥ 1` = fret `k - 1` (so class 1 = open, and
/// class 20 = fret 19). This is the emission contract CrispASR's ABI must match.
const int kTabClasses = 21;

/// The highest fret an emission class can name (class 20 → fret 19).
const int kTabMaxFret = kTabClasses - 2;

int _fretOfClass(int cls) => cls - 1; // class 1 → fret 0 (open)

/// Per-frame TabCNN emissions: [nFrames] frames × [kTabStrings] strings ×
/// [kTabClasses] classes of **log-probabilities**, flattened row-major
/// (frame, string, class). [hopSeconds] is the frame hop so the caller can align
/// the decoded tab to its own time grid. Log-probs (not probs) so the DP sums
/// costs without ever taking log(0).
class TabEmissionFrames {
  TabEmissionFrames({
    required this.nFrames,
    required this.hopSeconds,
    required this.logProbs,
  }) : assert(logProbs.length == nFrames * kTabStrings * kTabClasses);

  final int nFrames;
  final double hopSeconds;
  final Float64List logProbs;

  /// The log-probability of [cls] on [string] at [frame].
  double at(int frame, int string, int cls) =>
      logProbs[(frame * kTabStrings + string) * kTabClasses + cls];
}

/// The emission scorer CrispASR ships (GP-FX-augmented TabCNN): audio →
/// [TabEmissionFrames] of log-probs, with NO decoding or smoothing inside the
/// network. Returns null when unavailable (no model / web / load failure) so the
/// caller falls back to its symbolic/heuristic tab paths. Mirrors the
/// `F0Estimator` seam — the model provides emissions, we provide the decode.
abstract interface class TabEmissionModel {
  TabEmissionFrames? emit(Float64List monoAudio, int sampleRate);
}

/// The cost of a string moving between classes on consecutive frames: staying
/// put is free, a note starting/stopping costs [onsetCost], and shifting the
/// finger to a different fret mid-note costs [fretStepCost] per fret moved (a
/// slide is more expensive than a sustain, so a one-frame emission spike to a
/// far fret loses to holding position).
double _transition(int a, int b, double fretStepCost, double onsetCost) {
  if (a == 0 && b == 0) return 0; // silent → silent
  if (a == 0 || b == 0) return onsetCost; // note starts or ends
  return fretStepCost * (_fretOfClass(a) - _fretOfClass(b)).abs();
}

/// Decodes [e] into one [Fretting] per frame via a per-string temporal Viterbi.
/// Each string independently finds the min-cost fret path (emission cost =
/// −log-prob, plus [_transition]); silent strings are omitted from the fretting.
/// The result is a strict improvement over the per-frame argmax the TabCNN paper
/// reports. (Cross-string hand-span coupling within a frame is a documented
/// refinement — see the handoff doc; per-string smoothing is the honest v1.)
List<Fretting> decodeTabEmissions(
  TabEmissionFrames e, {
  double fretStepCost = 0.6,
  double onsetCost = 0.0,
}) {
  if (e.nFrames == 0) return [];
  // One Viterbi per string → a class per frame.
  final paths = List<List<int>>.generate(kTabStrings, (s) {
    var dp = [for (var c = 0; c < kTabClasses; c++) -e.at(0, s, c)];
    final back = <List<int>>[];
    for (var t = 1; t < e.nFrames; t++) {
      final next = List<double>.filled(kTabClasses, double.infinity);
      final bp = List<int>.filled(kTabClasses, 0);
      for (var c = 0; c < kTabClasses; c++) {
        final emit = -e.at(t, s, c);
        for (var p = 0; p < kTabClasses; p++) {
          final total =
              dp[p] + emit + _transition(p, c, fretStepCost, onsetCost);
          if (total < next[c]) {
            next[c] = total;
            bp[c] = p;
          }
        }
      }
      dp = next;
      back.add(bp);
    }
    // Backtrack from the best final class.
    var best = 0;
    for (var c = 1; c < kTabClasses; c++) {
      if (dp[c] < dp[best]) best = c;
    }
    final path = List<int>.filled(e.nFrames, 0);
    path[e.nFrames - 1] = best;
    for (var t = e.nFrames - 1; t > 0; t--) {
      path[t - 1] = back[t - 1][path[t]];
    }
    return path;
  });

  return [
    for (var t = 0; t < e.nFrames; t++)
      {
        for (var s = 0; s < kTabStrings; s++)
          if (paths[s][t] != 0) s: _fretOfClass(paths[s][t]),
      },
  ];
}

/// Collapses a per-frame fretting sequence into run-length events — each an
/// unbroken run of the SAME fretting and how many frames it spans — so a later
/// rhythm/quantise stage can turn frame counts (× [TabEmissionFrames.hopSeconds])
/// into note durations. Adjacent identical frettings (incl. runs of silence)
/// merge; the run count always sums back to the input length.
List<(Fretting fretting, int frames)> collapseTabFrames(
  List<Fretting> perFrame,
) {
  final out = <(Fretting, int)>[];
  for (final f in perFrame) {
    if (out.isNotEmpty && _sameFretting(out.last.$1, f)) {
      out[out.length - 1] = (out.last.$1, out.last.$2 + 1);
    } else {
      out.add((f, 1));
    }
  }
  return out;
}

bool _sameFretting(Fretting a, Fretting b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}
