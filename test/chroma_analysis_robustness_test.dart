// Robustness of the chord (chroma) detector — the Chord listener feeds it the
// same untrusted mic frames as the pitch detector. It must never throw and
// never emit a non-finite field (a NaN would poison the visualiser + candidate
// scores). Regression coverage for two real bugs: an empty/1-sample window
// crashed on `clamp(1, 0)`, and a NaN/Inf frame leaked a non-finite energy that
// slipped past the silence gate (`NaN < gate` is false).

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/chroma_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void _finite(ChordReading r) {
  expect(r.energy.isFinite, isTrue, reason: 'energy ${r.energy}');
  expect(r.chroma.length, 12);
  for (final c in r.chroma) {
    expect(c.isFinite, isTrue, reason: 'chroma bin $c');
  }
  for (final cand in r.candidates) {
    expect(cand.score.isFinite, isTrue, reason: 'score ${cand.score}');
  }
}

Float64List _fill(int n, double v) => Float64List(n)..fillRange(0, n, v);

// Sum of sines at [midis] — a synthetic chord in a full detector window.
Float64List _chord(int n, List<int> midis, {int sr = 44100}) {
  final out = Float64List(n);
  for (final m in midis) {
    final f = 440.0 * pow(2.0, (m - 69) / 12.0);
    for (var i = 0; i < n; i++) {
      out[i] += 0.3 * sin(2 * pi * f * i / sr);
    }
  }
  return out;
}

void main() {
  final det = ChordDetector();
  final w = det.windowSize; // 4096

  group('degenerate windows never throw (the clamp-crash fix)', () {
    test('empty and tiny windows return a finite silent reading', () {
      for (final len in [0, 1, 2, 3, 5, 16]) {
        final r = det.analyze(Float64List(len));
        _finite(r);
        expect(r.hasChord, isFalse);
      }
      // chromagram() shares the FFT path — also crash-safe + finite.
      for (final len in [0, 1, 2]) {
        final c = det.chromagram(Float64List(len));
        expect(c.length, 12);
        expect(c.every((x) => x.isFinite), isTrue);
      }
    });

    test('silence, DC and a constant are finite + chordless', () {
      for (final v in [0.0, 0.5, -1.0]) {
        final r = det.analyze(_fill(w, v));
        _finite(r);
        expect(r.hasChord, isFalse);
      }
    });
  });

  group('NON-FINITE frames must not leak NaN/Inf (the gate fix)', () {
    test('an all-NaN window → clean silence, finite energy', () {
      final r = det.analyze(_fill(w, double.nan));
      _finite(r);
      expect(r.hasChord, isFalse);
      expect(r.energy, 0.0);
    });

    test('all-Inf, and a single bad sample in a real chord, stay finite', () {
      _finite(det.analyze(_fill(w, double.infinity)));
      for (final bad in [double.nan, double.infinity, -double.infinity]) {
        final buf = _chord(w, const [60, 64, 67]); // C major
        buf[w ~/ 2] = bad;
        _finite(det.analyze(buf));
      }
    });
  });

  test('random noise across seeds never throws and stays finite', () {
    for (var seed = 0; seed < 30; seed++) {
      final r = Random(seed);
      final buf = Float64List(w);
      for (var i = 0; i < w; i++) {
        buf[i] = r.nextDouble() * 2 - 1;
      }
      _finite(det.analyze(buf));
    }
  });

  test('a clean C-major chord still matches (the guards did not break it)', () {
    final r = det.analyze(_chord(w, const [60, 64, 67])); // C E G
    _finite(r);
    expect(r.hasChord, isTrue);
    expect(r.best!.name, 'C');
  });
}
