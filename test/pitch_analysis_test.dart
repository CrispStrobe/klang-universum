// test/pitch_analysis_test.dart
//
// Validates the monophonic pitch detector against synth.dart's own tones — so
// the capture-layer math is proven end-to-end without needing a microphone.
// We synthesize a note (cello timbre, harmonics and all), hand the middle
// window to the detector, and assert it recovers the pitch and the intonation.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:flutter_test/flutter_test.dart';

/// Render a steady tone at [freq] and return a centred analysis window,
/// avoiding the attack/decay edges so we test the sustained portion.
Float64List _window(double freq, PitchDetector d, {Instrument? voice}) {
  final samples = renderSegments(
    [
      (freqs: [freq], ms: 500),
    ],
    sampleRate: d.sampleRate,
    timbre: voice == null ? null : timbreFor(voice),
  );
  final start = (samples.length - d.windowSize) ~/ 2;
  final out = Float64List(d.windowSize);
  for (var i = 0; i < d.windowSize; i++) {
    out[i] = samples[start + i] / 32768.0;
  }
  return out;
}

void main() {
  final detector = PitchDetector();

  group('detects synthesized pitches', () {
    // Cello open strings + a couple of high references. C2 is the acid test:
    // an FFT at this window could not resolve it, MPM does.
    final cases = <String, double>{
      'C2 (cello low C)': 65.41,
      'G2 (cello G)': 98.00,
      'D3 (cello D)': 146.83,
      'A3 (cello A)': 220.00,
      'A4 (reference)': 440.00,
      'A5': 880.00,
    };
    cases.forEach((name, freq) {
      test(name, () {
        final r = detector.analyze(_window(freq, detector));
        expect(r.hasPitch, isTrue, reason: '$name should be detected');
        // Within 3 cents of the true frequency.
        final cents = 1200 * (log(r.frequency / freq) / log(2));
        expect(
          cents.abs(),
          lessThan(3),
          reason: '$name off by ${cents.toStringAsFixed(2)}¢',
        );
        expect(r.clarity, greaterThan(0.8));
      });
    });
  });

  test('works with the cello timbre (rich harmonics), no octave error', () {
    final r =
        detector.analyze(_window(98.0, detector, voice: Instrument.cello));
    expect(r.hasPitch, isTrue);
    // The classic failure mode is snapping an octave down/up; guard it.
    expect(r.frequency, closeTo(98.0, 2.0));
    expect(r.noteName, 'G2');
  });

  // Regression: the key-maxima scan used to start at `minLag` rather than 1.
  // The NSDF zero crossing that opens the fundamental's segment sits near 3T/4,
  // which for short periods falls BELOW minLag — so that segment was never
  // opened, the peak at T was skipped, and the peak at 2T won: the pitch came
  // back an octave low AT FULL CLARITY. With minLag = 44100/2000 = 22 that hit
  // everything above ~1503 Hz — the top quarter of the detector's own declared
  // range (maxFrequency = 2000). The suite missed it by topping out at A5.
  group('high register (regression: octave halving above ~1503 Hz)', () {
    final cases = <String, double>{
      'G6': 1567.98,
      'A6': 1760.00,
      'B6': 1975.53,
    };
    cases.forEach((name, freq) {
      test('$name is detected, not reported an octave low', () {
        final r = detector.analyze(_window(freq, detector));
        expect(r.hasPitch, isTrue, reason: '$name should be detected');
        expect(
          r.frequency,
          closeTo(freq, freq * 0.02),
          reason: '$name came back as ${r.frequency.toStringAsFixed(1)} Hz',
        );
      });
    });

    test('a tone above maxFrequency is silent, not halved into range', () {
      // 3000 Hz is out of range: it must report nothing rather than be folded
      // to a confident (and wrong) ~1500 Hz.
      final r = detector.analyze(_window(3000.0, detector));
      expect(
        r.hasPitch,
        isFalse,
        reason: 'got ${r.frequency.toStringAsFixed(1)} Hz',
      );
    });
  });

  test('reports intonation error in cents (fretless use-case)', () {
    // 25 cents sharp of A3 (220 Hz).
    final sharp = 220.0 * pow(2, 25 / 1200);
    final r = detector.analyze(_window(sharp.toDouble(), detector));
    expect(r.nearestMidi, 57); // A3
    expect(r.cents, closeTo(25, 2));
    expect(r.noteName, 'A3');
  });

  test('silence and noise produce no pitch', () {
    final silence = Float64List(detector.windowSize); // all zeros
    expect(detector.analyze(silence).hasPitch, isFalse);

    final rng = Random(42);
    final noise = Float64List(detector.windowSize);
    for (var i = 0; i < noise.length; i++) {
      noise[i] = (rng.nextDouble() * 2 - 1) * 0.5;
    }
    expect(
      detector.analyze(noise).hasPitch,
      isFalse,
      reason: 'white noise is not periodic — should be rejected',
    );
  });

  test('pcm16ToFloat round-trips a known ramp', () {
    final bytes = Uint8List(8);
    final bd = ByteData.sublistView(bytes);
    bd.setInt16(0, 0, Endian.little);
    bd.setInt16(2, 16384, Endian.little); // +0.5
    bd.setInt16(4, -32768, Endian.little); // -1.0
    bd.setInt16(6, 32767, Endian.little); // ~+1.0
    final f = pcm16ToFloat(bytes);
    expect(f[0], closeTo(0.0, 1e-9));
    expect(f[1], closeTo(0.5, 1e-9));
    expect(f[2], closeTo(-1.0, 1e-9));
    expect(f[3], closeTo(1.0, 1e-3));
  });
}
