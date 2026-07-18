// crisp_dsp: biquad EQ + dynamics (compressor/limiter/gate). Pure-math checks
// on DC/Nyquist response and level-dependent gain.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/biquad.dart';
import 'package:comet_beat/core/audio/crisp_dsp/dynamics.dart';
import 'package:flutter_test/flutter_test.dart';

const _sr = 44100.0;

Float64List _sine(double amp, double freq, int n) => Float64List.fromList([
      for (var i = 0; i < n; i++) amp * math.sin(2 * math.pi * freq * i / _sr),
    ]);

Float64List _dc(double v, int n) => Float64List.fromList(List.filled(n, v));

Float64List _nyquist(double amp, int n) =>
    Float64List.fromList([for (var i = 0; i < n; i++) i.isEven ? amp : -amp]);

double _peakLateHalf(Float64List x) {
  var p = 0.0;
  for (var i = x.length ~/ 2; i < x.length; i++) {
    p = math.max(p, x[i].abs());
  }
  return p;
}

void main() {
  group('biquad', () {
    test('mix == 0 is an exact identity copy', () {
      final x = _sine(0.5, 440, 512);
      final y = biquadFx(x, sampleRate: _sr, mix: 0);
      expect(y, x);
    });

    test('lowpass passes DC, kills Nyquist', () {
      final lpDc = biquadFx(
        _dc(1, 2048),
        sampleRate: _sr,
      );
      expect(lpDc.last, closeTo(1.0, 0.01)); // unity at DC

      final lpNy = biquadFx(
        _nyquist(1, 2048),
        sampleRate: _sr,
      );
      expect(_peakLateHalf(lpNy), lessThan(0.05)); // Nyquist crushed
    });

    test('highpass kills DC, passes Nyquist', () {
      final hpDc = biquadFx(
        _dc(1, 2048),
        kind: BiquadKind.highpass,
        sampleRate: _sr,
      );
      expect(_peakLateHalf(hpDc), lessThan(0.05)); // DC blocked

      final hpNy = biquadFx(
        _nyquist(1, 2048),
        kind: BiquadKind.highpass,
        sampleRate: _sr,
      );
      expect(_peakLateHalf(hpNy), greaterThan(0.9)); // Nyquist passes
    });

    test('a peaking boost raises energy at its centre frequency', () {
      final x = _sine(0.3, 1000, 4096);
      final flat = x;
      final boosted = parametricEqFx(
        x,
        const [EqBand(BiquadKind.peaking, freq: 1000, q: 2, gainDb: 12)],
        sampleRate: _sr,
      );
      expect(_peakLateHalf(boosted), greaterThan(_peakLateHalf(flat)));
    });

    test('empty EQ is an identity', () {
      final x = _sine(0.4, 300, 512);
      expect(parametricEqFx(x, const [], sampleRate: _sr), x);
    });
  });

  group('dynamics', () {
    test('compressor: mix == 0 identity', () {
      final x = _sine(0.8, 440, 512);
      expect(compressorFx(x, sampleRate: _sr, mix: 0), x);
    });

    test('compressor clamps a loud sustained tone toward the threshold', () {
      final loud = _sine(1.0, 440, 8820); // 0 dBFS peak
      final y = compressorFx(
        loud,
        sampleRate: _sr,
        attackMs: 5,
      );
      // ratio 4 at +18 dB over → ~-13.5 dB → gain ~0.21; well under the input.
      expect(_peakLateHalf(y), lessThan(0.5));
      expect(_peakLateHalf(loud), closeTo(1.0, 0.01));
    });

    test('compressor leaves a quiet (sub-threshold) tone ~unchanged', () {
      final quiet = _sine(0.05, 440, 4096); // ~-26 dB, below -18
      final y = compressorFx(quiet, sampleRate: _sr);
      expect(_peakLateHalf(y), closeTo(0.05, 0.01));
    });

    test('limiter holds the peak near the ceiling', () {
      final loud = _sine(1.0, 440, 8820);
      final y = limiterFx(loud, sampleRate: _sr);
      expect(_peakLateHalf(y), lessThan(0.95)); // pulled below 0 dBFS
    });

    test('gate opens for loud signal, closes for quiet', () {
      final loud = _sine(0.5, 440, 4096); // -6 dB, above -40 gate
      final quiet = _sine(0.003, 440, 4096); // ~-50 dB, below the gate
      final gLoud = gateFx(loud, sampleRate: _sr);
      final gQuiet = gateFx(quiet, sampleRate: _sr);
      expect(_peakLateHalf(gLoud), closeTo(0.5, 0.05)); // passes
      expect(_peakLateHalf(gQuiet), lessThan(0.002)); // attenuated
    });
  });
}
