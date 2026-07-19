// Auto-loop-point detection — find a seamless SUSTAIN loop in a sample so a
// recorded voice / loaded WAV can hold a note instead of dying at the sample's
// end. Pure Dart DSP, NON-DESTRUCTIVE (only picks loop points; never edits the
// PCM). Pairs with SampleInstrument's loop rendering (forward or ping-pong).

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tracker_engine.dart';

/// A detected loop region: play `[0, loopStart+loopLength)` once, then repeat
/// `[loopStart, loopStart+loopLength)` (the SampleInstrument loop convention).
typedef LoopPoints = ({int loopStart, int loopLength});

/// Find a seamless sustain loop in [pcm] (mono, roughly ±1). Returns null when
/// the sample is too short, (near-)silent, or no confident loop is found —
/// leave it a one-shot then.
///
/// Strategy: skip the attack (start the loop ~[startFraction] in, at a rising
/// zero crossing where the signal has settled), then scan later rising zero
/// crossings for the loop END whose following [window] samples best match (by
/// normalized cross-correlation, so a decaying-but-periodic tone still matches)
/// the [window] at the loop start. A loop length that's an integer number of
/// periods makes the content after the end equal the content after the start,
/// so the wrap is click-free. Rejects matches below [minCorrelation].
LoopPoints? findLoopPoints(
  Float64List pcm, {
  int minLoopLength = 256,
  int window = 128,
  double startFraction = 0.25,
  double minCorrelation = 0.5,
}) {
  final n = pcm.length;
  if (n < minLoopLength + window * 2) return null;

  // Trim trailing near-silence (a recording's tail) so we never loop silence.
  var end = n;
  while (end > minLoopLength && pcm[end - 1].abs() < 1e-4) {
    end--;
  }
  if (end < minLoopLength + window * 2) return null;

  // Reject an overall (near-)silent buffer.
  var energy = 0.0;
  for (var i = 0; i < end; i++) {
    energy += pcm[i] * pcm[i];
  }
  if (energy / end < 1e-8) return null;

  // Loop start: ~startFraction in (past a typical attack), at a rising zero
  // crossing so the seam lands on a matching phase.
  final startGuess = (end * startFraction).floor();
  final loopStart = _risingZeroCrossAtOrAfter(pcm, startGuess, end - window);
  if (loopStart < 0) return null;

  // Reference window at the loop start.
  var refNorm = 0.0;
  for (var w = 0; w < window; w++) {
    refNorm += pcm[loopStart + w] * pcm[loopStart + w];
  }
  refNorm = sqrt(refNorm);
  if (refNorm < 1e-9) return null;

  // Search the loop END among rising zero crossings ≥ loopStart+minLoopLength.
  final searchFrom = loopStart + minLoopLength;
  final maxEnd = end - window; // window [e, e+window) must fit
  var bestEnd = -1;
  var bestCorr = -2.0;
  for (var e = searchFrom; e < maxEnd; e++) {
    if (!(pcm[e - 1] <= 0 && pcm[e] > 0)) continue; // rising zero crossing
    var dot = 0.0;
    var norm = 0.0;
    for (var w = 0; w < window; w++) {
      final b = pcm[e + w];
      dot += pcm[loopStart + w] * b;
      norm += b * b;
    }
    norm = sqrt(norm);
    if (norm < 1e-9) continue;
    final corr = dot / (refNorm * norm);
    if (corr > bestCorr) {
      bestCorr = corr;
      bestEnd = e;
    }
  }
  if (bestEnd < 0 || bestCorr < minCorrelation) return null;
  return (loopStart: loopStart, loopLength: bestEnd - loopStart);
}

/// The first rising zero crossing (`pcm[i-1] <= 0 < pcm[i]`) in `[from, limit)`,
/// or -1 if none.
int _risingZeroCrossAtOrAfter(Float64List pcm, int from, int limit) {
  final start = from < 1 ? 1 : from;
  for (var i = start; i < limit; i++) {
    if (pcm[i - 1] <= 0 && pcm[i] > 0) return i;
  }
  return -1;
}

/// Build a [SampleInstrument] from a raw recording, auto-detecting a sustain
/// loop so a held note rings instead of dying at the sample end. Falls back to a
/// one-shot (no loop) when [findLoopPoints] finds nothing confident. [pingPong]
/// makes the detected loop bidirectional.
SampleInstrument autoLoopedSample(
  String id,
  Float64List pcm, {
  int baseMidi = 60,
  bool pingPong = false,
}) {
  final lp = findLoopPoints(pcm);
  return SampleInstrument(
    id,
    pcm,
    baseMidi: baseMidi,
    loopStart: lp?.loopStart ?? 0,
    loopLength: lp?.loopLength ?? 0,
    pingPong: lp != null && pingPong,
  );
}
