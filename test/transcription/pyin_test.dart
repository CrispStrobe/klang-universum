// S1 — pYIN F0 estimator. Tests the per-frame pitch track directly (cents
// accuracy, vibrato robustness, and — the whole point over MPM — NO octave
// errors on a scale). Synthetic sines we control; the real-recording check is
// a documented CLI demo once S5 lands.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/pyin.dart';
import 'package:flutter_test/flutter_test.dart';

const _sr = 44100;

double _midiToHz(int m) => 440 * pow(2, (m - 69) / 12).toDouble();
int _nearestMidi(double hz) => (69 + 12 * (log(hz / 440) / ln2)).round();

Float64List _sine(double hz, {double seconds = 0.5, double amp = 0.5}) {
  final n = (seconds * _sr).round();
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = amp * sin(2 * pi * hz * i / _sr);
  }
  return out;
}

// A sine with sinusoidal vibrato of ±[depthCents] at [rateHz].
Float64List _vibrato(
  double centreHz,
  double depthCents,
  double rateHz, {
  double seconds = 0.6,
}) {
  final n = (seconds * _sr).round();
  final out = Float64List(n);
  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / _sr;
    final f = centreHz *
        pow(2, depthCents / 1200 * sin(2 * pi * rateHz * t)).toDouble();
    phase += f / _sr;
    out[i] = 0.5 * sin(2 * pi * phase);
  }
  return out;
}

Float64List _concat(List<Float64List> parts) {
  final total = parts.fold<int>(0, (s, p) => s + p.length);
  final out = Float64List(total);
  var off = 0;
  for (final p in parts) {
    out.setAll(off, p);
    off += p.length;
  }
  return out;
}

Iterable<PitchFrame> _voiced(PitchTrack t) =>
    t.where((f) => f.f0Hz > 0 && f.voicedProb > 0.5);

void main() {
  test('a pure tone reads its pitch to within a few cents', () {
    final t = pyinF0(_sine(_midiToHz(69))); // A4
    final v = _voiced(t).toList();
    expect(v, isNotEmpty);
    final mid = v[v.length ~/ 2];
    expect(centsBetween(mid.f0Hz, 440).abs(), lessThan(5));
    expect(mid.voicedProb, greaterThan(0.8));
  });

  test('vibrato is tracked; its median cancels to the centre pitch', () {
    final t = pyinF0(_vibrato(440, 40, 6)); // ±40 cents @ 6 Hz
    final hz = _voiced(t).map((f) => f.f0Hz).toList()..sort();
    expect(hz, isNotEmpty);
    final median = hz[hz.length ~/ 2];
    expect(centsBetween(median, 440).abs(), lessThan(20));
  });

  test('NO octave errors across a C major scale (the win over MPM)', () {
    const played = [60, 62, 64, 65, 67, 69, 71, 72];
    final rest = Float64List((0.06 * _sr).round()); // silence between notes
    final t = pyinF0(
      _concat([
        for (final m in played) ...[_sine(_midiToHz(m), seconds: 0.35), rest],
      ]),
    );
    final v = _voiced(t).toList();
    expect(v.length, greaterThan(20));
    // Every confident frame is within a semitone of a PLAYED note. An OCTAVE
    // error (e.g. C4→C3, 12 semitones off) would fail this; a ±1 boundary smear
    // is allowed.
    for (final f in v) {
      final midi = _nearestMidi(f.f0Hz);
      expect(
        played.any((p) => (midi - p).abs() <= 1),
        isTrue,
        reason: 'octave/spurious pitch: ${f.f0Hz.toStringAsFixed(1)} Hz '
            '(midi $midi) at ${f.timeMs.toStringAsFixed(0)}ms',
      );
    }
    // …and it actually finds most of the scale, not just one note.
    final found = {for (final f in v) _nearestMidi(f.f0Hz)};
    expect(found.length, greaterThanOrEqualTo(6));
  });

  test('silence and too-short input are safe', () {
    expect(_voiced(pyinF0(Float64List(_sr))), isEmpty); // 1s of zeros
    expect(pyinF0(Float64List(100)), isEmpty); // shorter than a window
  });
}
