// lib/core/audio/transcription/drums.dart
//
// W-DRUMS (DSP path) — transcribe a drum recording into timed hits classified as
// kick / snare / hat. Pure Dart, no model: it reuses the spectral-flux onset
// detection from the rhythm chain (detectRhythm) and the SAME timbre classifier
// the beatbox capture uses (beat_capture.classifyHit), so a recorded loop and a
// beatboxed one read the same way. Pairs with the DrumKit / Tracker: the hits can
// seed a drum pattern.
//
// Per onset it measures two features on a short window at the attack: the
// zero-crossing rate (low for a kick, mid for a snare, high for a hat) and
// whether low-frequency energy dominates (a kick's boom) — exactly the inputs
// classifyHit expects.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/beat_capture.dart' show classifyHit;
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/core/audio/transcription/rhythm.dart'
    show detectRhythm;

/// A classified drum onset.
typedef DrumHit = ({double timeMs, Drum drum});

const int _win = 1024; // ~23 ms attack window at 44.1 kHz
const double _lowHz = 200; // "low" band for the kick test

/// Transcribe [mono] into classified [DrumHit]s. Onsets come from the rhythm
/// chain's spectral-flux detector; each is classified by its attack timbre.
List<DrumHit> transcribeDrums(Float64List mono, {int sampleRate = 44100}) {
  final grid = detectRhythm(mono, sampleRate: sampleRate);
  final hits = <DrumHit>[];
  for (final onMs in grid.onsetMs) {
    final start = (onMs / 1000 * sampleRate).round();
    if (start < 0 || start + 2 >= mono.length) continue;
    final f = _features(mono, start, sampleRate);
    final drum = classifyHit(zcr: f.zcr, pitchedLow: f.pitchedLow);
    hits.add((timeMs: onMs, drum: drum));
  }
  return hits;
}

/// Zero-crossing rate + low-band dominance on the attack window at [start].
({double zcr, bool pitchedLow}) _features(
  Float64List mono,
  int start,
  int sampleRate,
) {
  final n = math.min(_win, mono.length - start);
  if (n < 4) return (zcr: 0, pitchedLow: false);

  // Zero-crossing rate: fraction of adjacent samples that change sign. Matches
  // how the mic PitchDetector reports zcr (kick ≈ 0.005, snare ≈ 0.45, hat ≈ 0.67).
  var crossings = 0;
  for (var i = start + 1; i < start + n; i++) {
    if ((mono[i] >= 0) != (mono[i - 1] >= 0)) crossings++;
  }
  final zcr = crossings / (n - 1);

  // Low-band dominance: energy below _lowHz vs total, via the average number of
  // samples between zero-crossings ≈ the dominant half-period. A kick's boom
  // makes long stretches between crossings (a low fundamental).
  final domHz = crossings > 0 ? crossings / 2 * sampleRate / n : 0.0;
  var energy = 0.0;
  for (var i = start; i < start + n; i++) {
    energy += mono[i] * mono[i];
  }
  final rms = math.sqrt(energy / n);
  final pitchedLow = rms > 1e-3 && domHz > 0 && domHz < _lowHz;

  return (zcr: zcr, pitchedLow: pitchedLow);
}
