// Offline ERLE cross-check for the native AEC core.
//
// This is the C twin of test/echo_canceller_test.dart in the app: it drives the
// native aec_dsp_* core over FFI with a perfectly-aligned digital mix and
// asserts the same two properties — a linear echo is cancelled with high ERLE,
// and an independent near-end signal survives double-talk. Because aec_dsp.c is
// a faithful port of echo_canceller.dart, matching these thresholds proves the
// port introduced no algorithmic drift (real-device alignment is a separate,
// hardware concern handled by the miniaudio duplex host).
//
// Requires the native library. Build it first:
//   cmake -S native/aec -B native/aec/build && cmake --build native/aec/build
// then run from the package root (native/aec):
//   dart test
// The test auto-locates build/libaec(.dylib|.so|.dll); override with
// AEC_LIBRARY_PATH=/abs/path/to/lib.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:aec_fullduplex/aec_dsp.dart';
import 'package:flutter_test/flutter_test.dart';

String? _resolveLibrary() {
  final env = Platform.environment['AEC_LIBRARY_PATH'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) return env;
  final ext = Platform.isMacOS
      ? 'dylib'
      : Platform.isWindows
          ? 'dll'
          : 'so';
  final prefix = Platform.isWindows ? '' : 'lib';
  for (final name in ['aec', 'aec_dsp']) {
    for (final dir in [
      'build',
      'native/aec/build',
      'build/Release',
      'build/Debug',
    ]) {
      final p = '$dir/$prefix$name.$ext';
      if (File(p).existsSync()) return p;
    }
  }
  return null;
}

void main() {
  const b = 1024; // matches the Dart EchoCanceller default block size

  final libPath = _resolveLibrary();

  // A short synthetic speaker->mic impulse response (the "room"), < one block —
  // identical to test/echo_canceller_test.dart.
  final h = Float64List.fromList(
    [0.6, 0.0, -0.35, 0.0, 0.2, 0.0, -0.12, 0.08, 0.05, -0.03],
  );
  double echoAt(List<double> ref, int t) {
    var s = 0.0;
    for (var j = 0; j < h.length; j++) {
      if (t - j >= 0) s += h[j] * ref[t - j];
    }
    return s;
  }

  group('native AEC core (FFI cross-check)', () {
    test('cancels a linear echo — high ERLE (echo only)', () {
      final aec = AecDsp.create(blockSize: b, libraryPath: libPath);
      addTearDown(aec.dispose);

      final rng = Random(7);
      const blocks = 80;
      final ref =
          List<double>.generate(blocks * b, (_) => rng.nextDouble() * 2 - 1);

      var micEnergy = 0.0, outEnergy = 0.0;
      for (var bi = 0; bi < blocks; bi++) {
        final rb = Float64List(b);
        final mb = Float64List(b);
        for (var i = 0; i < b; i++) {
          final t = bi * b + i;
          rb[i] = ref[t];
          mb[i] = echoAt(ref, t); // mic = echo, no near-end
        }
        final out = aec.process(rb, mb);
        if (bi >= blocks - 10) {
          for (var i = 0; i < b; i++) {
            micEnergy += mb[i] * mb[i];
            outEnergy += out[i] * out[i];
          }
        }
      }
      final erleDb = 10 * (log(micEnergy / (outEnergy + 1e-12)) / ln10);
      expect(
        erleDb,
        greaterThan(20),
        reason: 'ERLE = ${erleDb.toStringAsFixed(1)} dB (want > 20)',
      );
    });

    test('preserves the near-end while removing the echo (double-talk)', () {
      final aec = AecDsp.create(blockSize: b, libraryPath: libPath);
      addTearDown(aec.dispose);

      final rng = Random(11);
      const blocks = 80;
      final ref =
          List<double>.generate(blocks * b, (_) => rng.nextDouble() * 2 - 1);
      double near(int t) => 0.3 * sin(2 * pi * 220 * t / 44100); // the "user"

      var nearErr = 0.0, nearEnergy = 0.0;
      for (var bi = 0; bi < blocks; bi++) {
        final rb = Float64List(b);
        final mb = Float64List(b);
        for (var i = 0; i < b; i++) {
          final t = bi * b + i;
          rb[i] = ref[t];
          mb[i] = echoAt(ref, t) + near(t); // double-talk
        }
        final out = aec.process(rb, mb);
        if (bi >= blocks - 10) {
          for (var i = 0; i < b; i++) {
            final t = bi * b + i;
            nearErr += (out[i] - near(t)) * (out[i] - near(t));
            nearEnergy += near(t) * near(t);
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

    test('the double-talk detector preserves the near-end better than linear',
        () {
      final rng = Random(23);
      const blocks = 120;
      const half = blocks ~/ 2; // near-end joins here (converge first)
      final ref =
          List<double>.generate(blocks * b, (_) => rng.nextDouble() * 2 - 1);
      double near(int t) => 0.3 * sin(2 * pi * 300 * t / 44100);

      // Run the converge-then-double-talk scenario, returning the near-end
      // error over the (fully double-talk) tail. With [useDtd] the native
      // detector freezes the filter on the near-end via aec.setAdapt.
      double runNearErr({required bool useDtd, void Function()? onFreeze}) {
        final aec = AecDsp.create(blockSize: b, libraryPath: libPath);
        final dtd = useDtd ? AecDtd.createFor(aec) : null;
        var err = 0.0;
        for (var bi = 0; bi < blocks; bi++) {
          final rb = Float64List(b);
          final mb = Float64List(b);
          for (var i = 0; i < b; i++) {
            final t = bi * b + i;
            rb[i] = ref[t];
            mb[i] = echoAt(ref, t) + (bi >= half ? near(t) : 0);
          }
          if (dtd != null) {
            final freeze = dtd.freeze;
            aec.setAdapt(!freeze);
            if (freeze) onFreeze?.call();
          }
          final out = aec.process(rb, mb);
          dtd?.update(rb, mb, out);
          if (bi >= blocks - 10) {
            for (var i = 0; i < b; i++) {
              final t = bi * b + i;
              err += (out[i] - near(t)) * (out[i] - near(t));
            }
          }
        }
        dtd?.dispose();
        aec.dispose();
        return err;
      }

      var frozen = 0;
      final linearErr = runNearErr(useDtd: false);
      final dtdErr = runNearErr(useDtd: true, onFreeze: () => frozen++);
      expect(frozen, greaterThan(0), reason: 'froze during double-talk');
      expect(
        dtdErr,
        lessThan(linearErr * 0.7),
        reason: 'near-end error: linear '
            '${linearErr.toStringAsFixed(3)} → DTD ${dtdErr.toStringAsFixed(3)}',
      );
    });

    test('reset clears the adaptive filter', () {
      final aec = AecDsp.create(blockSize: 256, libraryPath: libPath);
      addTearDown(aec.dispose);
      final ref =
          Float64List.fromList(List<double>.generate(256, (i) => sin(i * 0.3)));
      final mic = Float64List.fromList(
          List<double>.generate(256, (i) => 0.5 * sin(i * 0.3)));
      for (var i = 0; i < 20; i++) {
        aec.process(ref, mic);
      }
      aec.reset();
      // After reset the filter is zero, so the first block passes the mic
      // through unchanged (out == mic).
      final out = aec.process(ref, mic);
      var maxDiff = 0.0;
      for (var i = 0; i < 256; i++) {
        maxDiff = max(maxDiff, (out[i] - mic[i]).abs());
      }
      expect(maxDiff, lessThan(1e-9));
    });
  },
      skip: libPath == null
          ? 'native library not built — run: cmake -S native/aec -B '
              'native/aec/build && cmake --build native/aec/build'
          : false);
}
