// Headless unit test of the native ENGINE layer (aec_engine_*), with no audio
// device. It drives the exact realtime-callback processing via the test pump:
// PCM16 reference + mic go in through the same rings/framing/int16<->double
// conversion the device path uses, and the cleaned near-end comes back out.
// This pins down the plumbing around the DSP core that test/aec_erle_test.dart
// (pure aec_dsp) can't reach — ring alignment, block accumulation, clamping.

import 'dart:math';
import 'dart:typed_data';

import 'package:aec_fullduplex/src/engine_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lib_resolver.dart';

Int16List _toPcm16(List<double> x) {
  final out = Int16List(x.length);
  for (var i = 0; i < x.length; i++) {
    out[i] = (x[i] * 32767).round().clamp(-32768, 32767);
  }
  return out;
}

void main() {
  final libPath = resolveAecLibrary(requireEngine: true);

  // The same short room impulse response as the offline test, scaled reference
  // so echo (+ near) stays inside int16 range without clipping.
  final h = <double>[0.6, 0.0, -0.35, 0.0, 0.2, 0.0, -0.12, 0.08, 0.05, -0.03];
  double echoAt(List<double> ref, int t) {
    var s = 0.0;
    for (var j = 0; j < h.length; j++) {
      if (t - j >= 0) s += h[j] * ref[t - j];
    }
    return s;
  }

  group('AecEngineFfi (headless int16 data path)', () {
    test('raw mic tap round-trips the pumped PCM16 verbatim', () {
      final e = AecEngineFfi.create(frame: 256, libraryPath: libPath);
      addTearDown(e.dispose);
      final mic = _toPcm16(List.generate(256, (i) => 0.4 * sin(i * 0.21)));
      e.reference(Int16List(256)); // silence reference (nothing to cancel)
      e.pump(mic);
      final raw = e.readRaw();
      expect(raw.length, 256);
      expect(raw, orderedEquals(mic));
    });

    test('cancels a linear echo through the int16 engine — high ERLE', () {
      const frame = 256;
      const blocks = 200;
      final e = AecEngineFfi.create(frame: frame, libraryPath: libPath);
      addTearDown(e.dispose);

      final rng = Random(7);
      final ref = List<double>.generate(
          blocks * frame, (_) => (rng.nextDouble() * 2 - 1) * 0.4);

      var micEnergy = 0.0, cleanedEnergy = 0.0;
      for (var bi = 0; bi < blocks; bi++) {
        final r = <double>[];
        final m = <double>[];
        for (var i = 0; i < frame; i++) {
          final t = bi * frame + i;
          r.add(ref[t]);
          m.add(echoAt(ref, t)); // mic = echo only
        }
        e.reference(_toPcm16(r));
        e.pump(_toPcm16(m));
        final cleaned = e.read();
        expect(cleaned.length, frame); // exactly one block emitted per pump
        if (bi >= blocks - 20) {
          final micPcm = _toPcm16(m);
          for (var i = 0; i < frame; i++) {
            micEnergy += micPcm[i] * micPcm[i].toDouble();
            cleanedEnergy += cleaned[i] * cleaned[i].toDouble();
          }
        }
      }
      final erleDb = 10 * (log(micEnergy / (cleanedEnergy + 1e-9)) / ln10);
      expect(
        erleDb,
        greaterThan(20),
        reason: 'engine ERLE = ${erleDb.toStringAsFixed(1)} dB (want > 20)',
      );
    });

    test('preserves the near-end through the engine (double-talk)', () {
      const frame = 256;
      const blocks = 200;
      final e = AecEngineFfi.create(frame: frame, libraryPath: libPath);
      addTearDown(e.dispose);

      final rng = Random(11);
      final ref = List<double>.generate(
          blocks * frame, (_) => (rng.nextDouble() * 2 - 1) * 0.4);
      double near(int t) => 0.25 * sin(2 * pi * 220 * t / 44100);

      var nearErr = 0.0, nearEnergy = 0.0;
      for (var bi = 0; bi < blocks; bi++) {
        final r = <double>[];
        final m = <double>[];
        for (var i = 0; i < frame; i++) {
          final t = bi * frame + i;
          r.add(ref[t]);
          m.add(echoAt(ref, t) + near(t));
        }
        e.reference(_toPcm16(r));
        e.pump(_toPcm16(m));
        final cleaned = e.read();
        if (bi >= blocks - 20) {
          for (var i = 0; i < frame; i++) {
            final t = bi * frame + i;
            final nearPcm = near(t) * 32767;
            nearErr += (cleaned[i] - nearPcm) * (cleaned[i] - nearPcm);
            nearEnergy += nearPcm * nearPcm;
          }
        }
      }
      expect(
        nearErr,
        lessThan(nearEnergy * 0.3),
        reason:
            'near-end error ${(nearErr / nearEnergy * 100).toStringAsFixed(0)}%',
      );
    });

    test('the double-talk detector cuts near-end error vs the plain engine', () {
      // frame 1024 matches the AEC block size where the linear filter visibly
      // diverges under continuous double-talk (a 256-frame filter is already
      // robust, so the DTD has nothing to fix there).
      const frame = 1024;
      const blocks = 120;
      const half = blocks ~/ 2; // near-end joins here (converge on echo first)
      final rng = Random(29);
      final ref = List<double>.generate(
          blocks * frame, (_) => (rng.nextDouble() * 2 - 1) * 0.4);
      double near(int t) => 0.25 * sin(2 * pi * 300 * t / 44100);

      // Run the converge-then-double-talk scenario through the engine pump,
      // returning the near-end error over the (fully double-talk) tail.
      double runNearErr({required bool dtd}) {
        final e = AecEngineFfi.create(frame: frame, libraryPath: libPath);
        e.setDtd(dtd);
        var err = 0.0, energy = 0.0;
        for (var bi = 0; bi < blocks; bi++) {
          final r = <double>[];
          final m = <double>[];
          for (var i = 0; i < frame; i++) {
            final t = bi * frame + i;
            r.add(ref[t]);
            m.add(echoAt(ref, t) + (bi >= half ? near(t) : 0));
          }
          e.reference(_toPcm16(r));
          e.pump(_toPcm16(m));
          final cleaned = e.read();
          if (bi >= blocks - 20) {
            for (var i = 0; i < frame; i++) {
              final t = bi * frame + i;
              final nearPcm = near(t) * 32767;
              err += (cleaned[i] - nearPcm) * (cleaned[i] - nearPcm);
              energy += nearPcm * nearPcm;
            }
          }
        }
        e.dispose();
        return err / energy; // normalized near-end error
      }

      final plain = runNearErr(dtd: false);
      final withDtd = runNearErr(dtd: true);
      expect(
        withDtd,
        lessThan(plain * 0.7),
        reason: 'near-end error: plain '
            '${(plain * 100).toStringAsFixed(0)}% → '
            'DTD ${(withDtd * 100).toStringAsFixed(0)}%',
      );
    });
  },
      skip: libPath == null
          ? 'native library not built — run: cmake --build native/aec/build'
          : false);
}
