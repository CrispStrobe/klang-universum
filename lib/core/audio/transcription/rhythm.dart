// lib/core/audio/transcription/rhythm.dart
//
// Transcription — the rhythm chain (Worker 2 of docs/TRANSCRIPTION_HANDOFF.md).
// Pure Dart, clean-room from the papers, MIT-compatible + patent-free:
//   • onsets  — a spectral-flux envelope (STFT magnitude, half-wave-rectified
//               first difference summed over bins) + adaptive peak-picking.
//               (NOT SuperFlux.)
//   • tempo   — autocorrelation of the onset envelope, biased to a musical
//               60–180 BPM range, with parabolic peak interpolation.
//   • beats   — the Ellis dynamic-programming beat tracker ("Beat Tracking by
//               Dynamic Programming", Ellis 2007 — ISC/patent-free). (NOT
//               madmom's DBN.)
//   • quantise — map NoteEvents onto the beat grid → startBeat / beats.
//
// Consumes/produces only the frozen types in contracts.dart. Reuses the pure
// radix-2 `fft` from chroma_analysis.dart (read-only).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/chroma_analysis.dart' show fft;
import 'package:comet_beat/core/audio/transcription/contracts.dart';

const int _frameSize = 1024; // ~23 ms window at 44.1 kHz
const int _hop = 441; //        10 ms hop

/// Detects onsets, tempo and a beat grid from mono [mono] audio.
RhythmGrid detectRhythm(Float64List mono, {int sampleRate = 44100}) {
  final hopSec = _hop / sampleRate;
  final env = _onsetEnvelope(mono);
  if (env.length < 4) {
    return (bpm: 0, beatMs: const <double>[], onsetMs: const <double>[]);
  }

  final onsetFrames = _pickPeaks(env);
  final onsetMs = [for (final f in onsetFrames) f * hopSec * 1000];

  final periodFrames = _estimateTempoPeriod(env, hopSec);
  final bpm = periodFrames > 0 ? 60.0 / (periodFrames * hopSec) : 0.0;

  final beatFrames =
      periodFrames > 0 ? _ellisBeats(env, periodFrames) : const <int>[];
  final beatMs = [for (final f in beatFrames) f * hopSec * 1000];

  return (bpm: bpm, beatMs: beatMs, onsetMs: onsetMs);
}

/// The spectral-flux onset-strength envelope: one value per STFT hop.
Float64List _onsetEnvelope(Float64List mono) {
  if (mono.length < _frameSize) return Float64List(0);
  final frames = 1 + (mono.length - _frameSize) ~/ _hop;
  final env = Float64List(frames);
  final window = Float64List(_frameSize);
  for (var i = 0; i < _frameSize; i++) {
    window[i] =
        0.5 - 0.5 * math.cos(2 * math.pi * i / (_frameSize - 1)); // Hann
  }
  final re = Float64List(_frameSize);
  final im = Float64List(_frameSize);
  var prev = Float64List(_frameSize ~/ 2 + 1);
  for (var t = 0; t < frames; t++) {
    final start = t * _hop;
    for (var i = 0; i < _frameSize; i++) {
      re[i] = mono[start + i] * window[i];
      im[i] = 0;
    }
    fft(re, im);
    var flux = 0.0;
    final mag = Float64List(_frameSize ~/ 2 + 1);
    for (var k = 0; k <= _frameSize ~/ 2; k++) {
      final m = math.sqrt(re[k] * re[k] + im[k] * im[k]);
      mag[k] = m;
      final diff = m - prev[k];
      if (diff > 0) flux += diff; // half-wave rectified
    }
    env[t] = flux;
    prev = mag;
  }
  return env;
}

/// Adaptive peak-picking: a frame is an onset if it is a local maximum, sits a
/// margin above a moving average, and is far enough from the previous onset.
List<int> _pickPeaks(Float64List env) {
  final n = env.length;
  if (n == 0) return const [];
  var maxV = 0.0;
  for (final v in env) {
    if (v > maxV) maxV = v;
  }
  if (maxV <= 0) return const [];

  const w = 3; // local-max half-window
  const meanW = 12; // moving-average half-window
  const minGap = 6; // ≥60 ms between onsets
  final delta = 0.06 * maxV; // absolute margin over the local mean
  final peaks = <int>[];
  var last = -minGap - 1;
  for (var t = 0; t < n; t++) {
    var isLocalMax = true;
    for (var j = math.max(0, t - w); j <= math.min(n - 1, t + w); j++) {
      if (env[j] > env[t]) {
        isLocalMax = false;
        break;
      }
    }
    if (!isLocalMax) continue;
    var sum = 0.0;
    var cnt = 0;
    for (var j = math.max(0, t - meanW); j <= math.min(n - 1, t + meanW); j++) {
      sum += env[j];
      cnt++;
    }
    final mean = sum / cnt;
    if (env[t] >= mean + delta && env[t] > 0 && t - last >= minGap) {
      peaks.add(t);
      last = t;
    }
  }
  return peaks;
}

/// The beat period in (fractional) frames, from the onset-envelope
/// autocorrelation biased toward a musical tempo, with parabolic refinement.
double _estimateTempoPeriod(Float64List env, double hopSec) {
  final n = env.length;
  final minLag = (60.0 / 180 / hopSec).round(); // 180 BPM
  final maxLag = math.min(n - 1, (60.0 / 50 / hopSec).round()); // 50 BPM
  if (maxLag <= minLag) return 0;

  final ac = Float64List(maxLag + 1);
  for (var lag = minLag; lag <= maxLag; lag++) {
    var s = 0.0;
    for (var t = 0; t + lag < n; t++) {
      s += env[t] * env[t + lag];
    }
    // Tempo preference: a log-Gaussian centred on 120 BPM resolves octaves.
    final bpm = 60.0 / (lag * hopSec);
    final w = math.exp(-0.5 * math.pow(_log2(bpm / 120) / 0.9, 2));
    ac[lag] = s * w;
  }

  var peak = minLag;
  for (var lag = minLag; lag <= maxLag; lag++) {
    if (ac[lag] > ac[peak]) peak = lag;
  }
  if (peak <= minLag || peak >= maxLag) return peak.toDouble();
  // Parabolic interpolation for sub-frame lag (finer BPM than the 10 ms grid).
  final a = ac[peak - 1], b = ac[peak], c = ac[peak + 1];
  final denom = a - 2 * b + c;
  final offset = denom != 0 ? 0.5 * (a - c) / denom : 0.0;
  return peak + offset.clamp(-0.5, 0.5);
}

/// Ellis 2007 dynamic-programming beat tracker: pick a beat sequence that both
/// lands on strong onsets and keeps a near-constant [periodFrames] spacing.
List<int> _ellisBeats(Float64List env, double periodFrames) {
  final n = env.length;
  final period = periodFrames.round();
  if (period < 1 || n < period) return const [];

  // Normalise the local score so `tightness` is scale-independent.
  var maxV = 0.0;
  for (final v in env) {
    if (v > maxV) maxV = v;
  }
  if (maxV <= 0) return const [];
  final local = Float64List(n);
  for (var i = 0; i < n; i++) {
    local[i] = env[i] / maxV;
  }

  const tightness = 6.0;
  final cumscore = Float64List(n);
  final backlink = List<int>.filled(n, -1);
  final tauLo = math.max(1, (period / 2).round());
  final tauHi = (period * 2).round();
  for (var t = 0; t < n; t++) {
    var best = double.negativeInfinity;
    var bestTau = -1;
    final lo = t - tauHi, hi = t - tauLo;
    for (var tau = math.max(0, lo); tau <= hi; tau++) {
      final dev = _log2((t - tau) / period); // log-ratio deviation
      final score = cumscore[tau] - tightness * dev * dev;
      if (score > best) {
        best = score;
        bestTau = tau;
      }
    }
    if (bestTau >= 0) {
      cumscore[t] = local[t] + best;
      backlink[t] = bestTau;
    } else {
      cumscore[t] = local[t];
    }
  }

  // Start from the strongest cumulative score in the final window, backtrack.
  var end = n - 1;
  for (var t = math.max(0, n - period); t < n; t++) {
    if (cumscore[t] > cumscore[end]) end = t;
  }
  final beats = <int>[];
  var t = end;
  while (t >= 0) {
    beats.add(t);
    t = backlink[t];
  }
  final ordered = beats.reversed.toList();

  // Trim beats forced onto silence at the ends (e.g. frame 0, before the music
  // starts, or a trailing beat past the last onset) — no real onset there.
  final thresh = 0.05 * maxV;
  var lo = 0, hi = ordered.length - 1;
  while (lo <= hi && env[ordered[lo]] < thresh) {
    lo++;
  }
  while (hi >= lo && env[ordered[hi]] < thresh) {
    hi--;
  }
  return lo <= hi ? ordered.sublist(lo, hi + 1) : const <int>[];
}

/// Quantises [notes] onto [grid]'s beat times → fractional [startBeat] and a
/// [beats] duration snapped to a sixteenth-note grid.
List<GriddedNote> quantizeToGrid(List<NoteEvent> notes, RhythmGrid grid) {
  final beatMs = grid.beatMs;
  const subdiv = 4; // sixteenth grid
  if (beatMs.length < 2) {
    return [for (final n in notes) (note: n, startBeat: 0, beats: 1)];
  }
  final period = (beatMs.last - beatMs.first) / (beatMs.length - 1);
  double toBeat(double ms) {
    if (ms <= beatMs.first) return (ms - beatMs.first) / period;
    if (ms >= beatMs.last) {
      return (beatMs.length - 1) + (ms - beatMs.last) / period;
    }
    for (var i = 0; i < beatMs.length - 1; i++) {
      if (ms >= beatMs[i] && ms < beatMs[i + 1]) {
        return i + (ms - beatMs[i]) / (beatMs[i + 1] - beatMs[i]);
      }
    }
    return 0;
  }

  double snap(double beat) => (beat * subdiv).round() / subdiv;
  return [
    for (final n in notes)
      (
        note: n,
        startBeat: snap(toBeat(n.onMs)),
        beats: () {
          final d = snap(toBeat(n.offMs) - toBeat(n.onMs));
          return d <= 0 ? 1 / subdiv : d;
        }(),
      ),
  ];
}

double _log2(double x) => math.log(x <= 0 ? 1e-12 : x) / math.ln2;
