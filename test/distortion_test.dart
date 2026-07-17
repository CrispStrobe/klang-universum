// test/distortion_test.dart
//
// Waveshaping distortion set: pure, same-length, deterministic. Synthetic buffers.
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/distortion_test.dart

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/distortion.dart';
import 'package:flutter_test/flutter_test.dart';

Float64List _sine(int n, double hz, {double amp = 0.7, int sr = 44100}) {
  final b = Float64List(n);
  for (var i = 0; i < n; i++) {
    b[i] = amp * sin(2 * pi * hz * i / sr);
  }
  return b;
}

bool _finite(Float64List b) => b.every((v) => v.isFinite);
double _peak(Float64List b) => b.fold(0.0, (p, v) => max(p, v.abs()));
bool _differs(Float64List a, Float64List b) {
  for (var i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 1e-6) return true;
  }
  return false;
}

void main() {
  final dry = _sine(2000, 220);

  group('distortionFx — each shape', () {
    for (final kind in DistortionKind.values) {
      test('$kind: changes the signal, same length, finite, bounded', () {
        final out = distortionFx(dry, kind: kind, drive: 5);
        expect(out.length, dry.length);
        expect(_differs(dry, out), isTrue);
        expect(_finite(out), isTrue);
        expect(_peak(out), lessThanOrEqualTo(1.01));
      });

      test('$kind: mix 0 is the dry signal; deterministic', () {
        expect(_differs(dry, distortionFx(dry, kind: kind, mix: 0)), isFalse);
        final a = distortionFx(dry, kind: kind, drive: 5);
        final b = distortionFx(dry, kind: kind, drive: 5);
        expect(_differs(a, b), isFalse);
      });
    }
  });

  test('hardClip clamps to ±1', () {
    final over = Float64List.fromList([2.0, -2.0, 0.5, -0.25]);
    final out = distortionFx(over, kind: DistortionKind.hardClip, drive: 1);
    expect(out[0], closeTo(1.0, 1e-9));
    expect(out[1], closeTo(-1.0, 1e-9));
    expect(out[2], closeTo(0.5, 1e-9));
    expect(out[3], closeTo(-0.25, 1e-9));
  });

  test('softClip (tanh) saturates but stays inside ±1', () {
    final hot = _sine(1000, 220, amp: 1.0);
    final out = distortionFx(hot, drive: 6); // default kind is softClip (tanh)
    expect(_peak(out), lessThan(1.0)); // tanh never reaches ±1
    expect(_peak(out), greaterThan(0.9)); // but drives hard toward it
  });
}
