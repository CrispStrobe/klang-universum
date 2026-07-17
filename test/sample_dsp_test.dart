// crisp_dsp sample effects — resampler, granular pitch shift, formant shift, and
// the voice-effect palette. Pure Dart, tested against a synthetic sample.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/chroma_analysis.dart' show fft;
import 'package:comet_beat/core/audio/crisp_dsp/formant_shift.dart';
import 'package:comet_beat/core/audio/crisp_dsp/pitch_shift.dart';
import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/crisp_dsp/voice_fx.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

/// A voice-like tone: a harmonic series shaped by fixed formant peaks (~"ah").
/// A bare sine has no envelope to speak of, so it can't show a formant shift —
/// this is the signal these effects are actually built for.
Float64List _voice(double f0, int n, {int sr = 44100}) {
  final out = Float64List(n);
  const formants = [700.0, 1220.0, 2600.0];
  for (var h = 1; h * f0 < 8000; h++) {
    final fh = h * f0;
    var amp = 0.0;
    for (final fc in formants) {
      amp += 1.0 / (1 + pow((fh - fc) / 120.0, 2));
    }
    amp *= 1.0 / h;
    for (var i = 0; i < n; i++) {
      out[i] += amp * sin(2 * pi * fh * i / sr);
    }
  }
  var peak = 0.0;
  for (final s in out) {
    if (s.abs() > peak) peak = s.abs();
  }
  for (var i = 0; i < n; i++) {
    out[i] = out[i] / peak * 0.7;
  }
  return out;
}

/// Spectral centroid in Hz — where the energy sits. Moving the formants moves it.
double _centroid(Float64List x, {int sr = 44100}) {
  const n = 8192;
  final re = Float64List(n);
  final im = Float64List(n);
  for (var i = 0; i < n && i < x.length; i++) {
    re[i] = x[i] * (0.5 - 0.5 * cos(2 * pi * i / (n - 1)));
  }
  fft(re, im);
  var num = 0.0;
  var den = 0.0;
  for (var k = 1; k < n ~/ 2; k++) {
    final mag = sqrt(re[k] * re[k] + im[k] * im[k]);
    num += mag * k * sr / n;
    den += mag;
  }
  return den > 0 ? num / den : 0;
}

/// Cents between a detected frequency and the intended one.
double _cents(double got, double want) => 1200 * log(got / want) / log(2);

/// The pitch the app's own detector hears in the middle of [x].
double _detected(Float64List x) {
  final d = PitchDetector();
  final start = (x.length - d.windowSize) ~/ 2;
  final w = Float64List.fromList(x.sublist(start, start + d.windowSize));
  return d.analyze(w).frequency;
}

/// A [seconds]-long sine at [hz] (44.1 kHz), a stand-in for a recording.
Float64List _sine(double seconds, double hz, {int sr = 44100}) {
  final n = (seconds * sr).floor();
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = sin(2 * pi * hz * i / sr);
  }
  return out;
}

double _peak(Float64List b) {
  var p = 0.0;
  for (final v in b) {
    if (v.abs() > p) p = v.abs();
  }
  return p;
}

bool _finite(Float64List b) => b.every((v) => v.isFinite);

void main() {
  group('resampleLinear', () {
    test('ratio > 1 shortens, ratio < 1 lengthens', () {
      final s = _sine(0.1, 220);
      expect(resampleLinear(s, 2.0).length, (s.length / 2).floor());
      expect(resampleLinear(s, 0.5).length, s.length * 2);
    });

    test('ratio 1 preserves a constant signal', () {
      final dc = Float64List.fromList(List.filled(100, 0.5));
      final out = resampleLinear(dc, 1.0);
      expect(out.length, 100);
      expect(out.every((v) => (v - 0.5).abs() < 1e-9), isTrue);
    });

    test('degenerate input is empty, not a crash', () {
      expect(resampleLinear(Float64List(0), 2).length, 0);
      expect(resampleLinear(_sine(0.01, 220), 0).length, 0);
    });
  });

  group('resampleCubic', () {
    test('same length semantics as linear + finite', () {
      final s = _sine(0.1, 220);
      expect(resampleCubic(s, 2.0).length, (s.length / 2).floor());
      expect(resampleCubic(s, 0.5).length, s.length * 2);
      expect(_finite(resampleCubic(s, 1.5)), isTrue);
    });

    test('ratio 1 preserves a constant signal', () {
      final dc = Float64List.fromList(List.filled(100, 0.5));
      final out = resampleCubic(dc, 1.0);
      expect(out.length, 100);
      expect(out.every((v) => (v - 0.5).abs() < 1e-9), isTrue);
    });

    test('degenerate input is safe', () {
      expect(resampleCubic(Float64List(0), 2).length, 0);
      expect(resampleCubic(_sine(0.01, 220), 0).length, 0);
      expect(resampleCubic(Float64List.fromList([0.7]), 1.0), [0.7]);
    });

    test('reconstructs a pitched sine more accurately than linear', () {
      const hz = 3000.0, sr = 44100, ratio = 1.5;
      final s = _sine(0.05, hz); // _sine defaults to 44100 Hz
      final lin = resampleLinear(s, ratio);
      final cub = resampleCubic(s, ratio);
      expect(cub.length, lin.length);
      double rms(Float64List b) {
        var sum = 0.0;
        for (var i = 2; i < b.length - 2; i++) {
          final truth = sin(2 * pi * hz * (i * ratio) / sr);
          final e = b[i] - truth;
          sum += e * e;
        }
        return sqrt(sum / (b.length - 4));
      }

      final eLin = rms(lin), eCub = rms(cub);
      // Cubic is clearly closer to the true resampled sine than linear.
      expect(eCub, lessThan(eLin * 0.5));
    });
  });

  group('resampleGlide (pitch envelope)', () {
    test('a constant ratio matches resampleCubic', () {
      final s = _sine(0.02, 300);
      final outLen = (s.length / 1.5).floor();
      final glide = resampleGlide(
        s,
        ratioStart: 1.5,
        ratioEnd: 1.5,
        glideSamples: 100,
        outLen: outLen,
      );
      final fixed = resampleCubic(s, 1.5);
      final n = min(glide.length, fixed.length);
      for (var i = 2; i < n - 2; i++) {
        expect(glide[i], closeTo(fixed[i], 1e-6));
      }
    });

    test('a glide differs from a fixed ratio; finite + bounded', () {
      final s = _sine(0.1, 300);
      final glide = resampleGlide(
        s,
        ratioStart: 2.0,
        ratioEnd: 1.0,
        glideSamples: 1000,
        outLen: s.length,
      );
      final fixed = resampleCubic(s, 1.0);
      expect(glide.sublist(0, 500), isNot(equals(fixed.sublist(0, 500))));
      expect(_finite(glide), isTrue);
      expect(_peak(glide), lessThanOrEqualTo(1.01));
    });

    test('degenerate inputs are safe', () {
      final empty = resampleGlide(
        Float64List(0),
        ratioStart: 1,
        ratioEnd: 1,
        glideSamples: 10,
        outLen: 100,
      );
      expect(empty.length, 0);
      final zeroOut = resampleGlide(
        _sine(0.01, 220),
        ratioStart: 1,
        ratioEnd: 1,
        glideSamples: 10,
        outLen: 0,
      );
      expect(zeroOut.length, 0);
    });
  });

  group('granularPitchShift', () {
    test('zero semitones is identity', () {
      final s = _sine(0.2, 220);
      expect(identical(granularPitchShift(s, 0), s), isTrue);
    });

    test('a shift produces finite, audible output', () {
      final s = _sine(0.2, 220);
      final up = granularPitchShift(s, 12);
      expect(up.isNotEmpty, isTrue);
      expect(_finite(up), isTrue);
      expect(_peak(up), greaterThan(0.0));
    });
  });

  group('formantShift', () {
    test('zero shift is identity', () {
      final s = _sine(0.2, 220);
      expect(identical(formantShift(s, 0), s), isTrue);
    });

    test('a shift keeps the length, changes the content, stays finite', () {
      final s = _sine(0.2, 220);
      final shifted = formantShift(s, 0.5);
      expect(shifted.length, s.length);
      expect(_finite(shifted), isTrue);
      var same = true;
      for (var i = 0; i < s.length; i++) {
        if ((s[i] - shifted[i]).abs() > 1e-6) {
          same = false;
          break;
        }
      }
      expect(same, isFalse);
    });

    // Regression: this used to scale TIME-DOMAIN indices, which resamples the
    // frame — a PITCH shift, not a formant shift. The tests above pass happily
    // on a signal transposed by a fourth, so nothing caught it: a recorded C4
    // came back at +608 ¢ (chipmunk), −1893 ¢ (monster), −368 ¢ (deep), so the
    // voice channel played wildly out of tune against every other channel.
    // Pitch is the property the whole voice_fx contract rests on — pin it.
    group('pitch/level contract', () {
      const f0 = 261.63; // C4
      final src = _voice(f0, 44100);

      test('the pitch is untouched at every shift', () {
        for (final shift in [0.5, 0.4, -0.3, -0.5]) {
          final got = _detected(formantShift(src, shift));
          expect(got, greaterThan(0), reason: 'shift $shift lost the pitch');
          expect(
            _cents(got, f0).abs(),
            lessThan(25),
            reason: 'shift $shift moved the pitch by '
                '${_cents(got, f0).toStringAsFixed(0)}¢',
          );
        }
      });

      test('the formants actually move — up is brighter, down is darker', () {
        final dry = _centroid(src);
        expect(_centroid(formantShift(src, 0.5)), greaterThan(dry * 1.15));
        expect(_centroid(formantShift(src, -0.5)), lessThan(dry * 0.85));
      });

      test('the output never exceeds the input level', () {
        // Shifting the envelope up boosts bins the source barely occupied; a
        // 0.7-peak voice came out at 2.12 before the level cap — hard clipping
        // by the time it reaches PCM16.
        final dry = _peak(src);
        for (final shift in [0.5, 0.4, -0.3, -0.5]) {
          expect(
            _peak(formantShift(src, shift)),
            lessThanOrEqualTo(dry + 1e-9),
            reason: 'shift $shift overshoots the input peak',
          );
        }
      });

      test('a clip shorter than one frame returns audio, not silence', () {
        // frameCount = length ~/ hop meant anything under 512 samples skipped
        // the loop and returned a zero buffer — a silent channel, no error.
        for (final n in [200, 400, 511]) {
          final out = formantShift(_voice(f0, n), 0.5);
          expect(out.length, n);
          expect(_peak(out), greaterThan(0.0), reason: 'len $n went silent');
          expect(_finite(out), isTrue, reason: 'len $n not finite');
        }
      });
    });
  });

  group('applyVoiceEffect', () {
    final raw = _sine(0.2, 220);

    test('the in-tune presets keep a recorded note in tune', () {
      const f0 = 261.63; // C4
      final src = _voice(f0, 44100);
      for (final fx in kPitchPreservingVoiceEffects) {
        final got = _detected(applyVoiceEffect(src, fx));
        expect(got, greaterThan(0), reason: '$fx lost the pitch entirely');
        expect(
          _cents(got, f0).abs(),
          lessThan(35),
          reason: '$fx moved a recorded C4 by '
              '${_cents(got, f0).toStringAsFixed(0)}¢ — it must stay in tune '
              'for the grid note to mean anything',
        );
      }
    });

    test('the ring-modulated presets are the documented exception', () {
      // Ring modulation replaces each harmonic f with f ± carrier, so these
      // CANNOT preserve pitch — that is the effect. Pinned so the split stays
      // honest rather than drifting back into a blanket "all preserve pitch".
      const ringMod = {
        VoiceEffect.robot,
        VoiceEffect.alien,
        VoiceEffect.cyborg,
      };
      expect(
        kPitchPreservingVoiceEffects.intersection(ringMod),
        isEmpty,
        reason: 'ring-modulated presets must not claim to be in tune',
      );
      expect(
        {...kPitchPreservingVoiceEffects, ...ringMod},
        VoiceEffect.values.toSet(),
        reason: 'every preset must be classified one way or the other',
      );
    });

    test('every effect yields finite, audible output', () {
      for (final fx in VoiceEffect.values) {
        final out = applyVoiceEffect(raw, fx);
        expect(out.length, raw.length, reason: '$fx not length-preserving');
        expect(_finite(out), isTrue, reason: '$fx not finite');
        expect(_peak(out), greaterThan(0.0), reason: '$fx silent');
      }
    });

    test('normal is a faithful copy; robot changes the signal', () {
      final normal = applyVoiceEffect(raw, VoiceEffect.normal);
      expect(normal, equals(raw));
      final robot = applyVoiceEffect(raw, VoiceEffect.robot);
      expect(robot, isNot(equals(raw)));
      expect(robot.length, raw.length); // pitch/length preserving
    });
  });
}
