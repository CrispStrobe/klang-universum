// test/ring_mod_test.dart
//
// Ring modulator: pure, same-length, deterministic. The strong acceptance —
// ring-modulating a DC input with a carrier yields a pure carrier tone, which the
// app's MPM detector reads back at the carrier frequency.
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/ring_mod_test.dart

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/ring_mod.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

Float64List _dc(int n, double v) => Float64List(n)..fillRange(0, n, v);

bool _finite(Float64List b) => b.every((v) => v.isFinite);
double _peak(Float64List b) => b.fold(0.0, (p, v) => max(p, v.abs()));
bool _differs(Float64List a, Float64List b) {
  for (var i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 1e-6) return true;
  }
  return false;
}

void main() {
  test('mix 0 is the dry signal; length preserved', () {
    final dry = _dc(4000, 0.5);
    final out = ringModFx(dry, mix: 0);
    expect(out.length, dry.length);
    expect(_differs(dry, out), isFalse);
  });

  test('a DC input becomes a pure carrier tone (MPM reads the carrier)', () {
    const carrier = 262.0; // C4-ish, not the default carrier
    final out = ringModFx(_dc(20000, 0.5), carrierHz: carrier);
    final d = PitchDetector();
    final window = Float64List(d.windowSize);
    const offset = 4000;
    for (var i = 0; i < d.windowSize; i++) {
      window[i] = out[offset + i];
    }
    expect(d.analyze(window).frequency, closeTo(carrier, 13.0)); // ~5%
  });

  test('bounded (|wet| ≤ |input|), finite, deterministic, same length', () {
    final dry = _dc(8000, 0.5);
    final a = ringModFx(dry, carrierHz: 330);
    final b = ringModFx(dry, carrierHz: 330);
    expect(a.length, dry.length);
    expect(_finite(a), isTrue);
    expect(_peak(a), lessThanOrEqualTo(0.5 + 1e-9));
    expect(_differs(a, b), isFalse);
    expect(_differs(dry, a), isTrue);
  });
}
