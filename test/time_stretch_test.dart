// test/time_stretch_test.dart
//
// WSOLA time-stretch: change duration, keep pitch. The strong acceptance —
// stretch/compress a sine and the app's MPM detector still reads the SAME pitch.
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/time_stretch_test.dart

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/time_stretch.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

Float64List _sine(int n, double hz, {int sr = 44100}) {
  final b = Float64List(n);
  for (var i = 0; i < n; i++) {
    b[i] = 0.8 * sin(2 * pi * hz * i / sr);
  }
  return b;
}

bool _finite(Float64List b) => b.every((v) => v.isFinite);
double _peak(Float64List b) => b.fold(0.0, (p, v) => max(p, v.abs()));

/// MPM-detected frequency from a window in the middle of [b].
double _pitch(Float64List b) {
  final d = PitchDetector();
  expect(b.length, greaterThan(d.windowSize + 8000));
  final start = (b.length - d.windowSize) ~/ 2;
  final window = Float64List(d.windowSize);
  for (var i = 0; i < d.windowSize; i++) {
    window[i] = b[start + i];
  }
  return d.analyze(window).frequency;
}

void main() {
  group('timeStretch — duration changes, pitch is preserved', () {
    final dry = _sine(22050, 220); // ~0.5 s @ 220 Hz

    test('slower (factor 1.5): ~1.5× longer, still ~220 Hz', () {
      final out = timeStretch(dry, 1.5);
      expect(out.length, closeTo(dry.length * 1.5, 2048));
      expect(_pitch(out), closeTo(220.0, 11.0));
    });

    test('faster (factor 0.7): ~0.7× length, still ~220 Hz', () {
      final out = timeStretch(dry, 0.7);
      expect(out.length, closeTo(dry.length * 0.7, 2048));
      expect(_pitch(out), closeTo(220.0, 11.0));
    });

    test('factor 1.0: ~same length, ~220 Hz, finite + bounded', () {
      final out = timeStretch(dry, 1.0);
      expect(out.length, closeTo(dry.length, 2048));
      expect(_pitch(out), closeTo(220.0, 11.0));
      expect(_finite(out), isTrue);
      expect(_peak(out), lessThan(1.05));
    });
  });

  test('degenerate inputs are safe (empty)', () {
    expect(timeStretch(Float64List(0), 1.5).length, 0);
    expect(timeStretch(_sine(4000, 220), 0).length, 0);
    expect(timeStretch(_sine(4000, 220), -1).length, 0);
  });
}
