// RVC voice conversion: pure-logic tests (coarse-pitch mapping parity vs the
// Python oracle, feature alignment, the licence gate) + a gated offline smoke
// test (needs a USER-supplied RVC ONNX at COMET_RVC_MODEL).
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/model_license.dart';
import 'package:comet_beat/core/audio/transcription/rvc.dart';
import 'package:comet_beat/core/audio/transcription/rvc_model_store.dart';
import 'package:flutter_test/flutter_test.dart';

const String _dir = 'test/transcription';

Float32List readF32(String path) {
  final bd = ByteData.sublistView(File(path).readAsBytesSync());
  final n = bd.getInt32(0, Endian.little);
  final o = Float32List(n);
  for (var i = 0; i < n; i++) {
    o[i] = bd.getFloat32(4 + i * 4, Endian.little);
  }
  return o;
}

Int64List readI64(String path) {
  final bd = ByteData.sublistView(File(path).readAsBytesSync());
  final n = bd.getInt32(0, Endian.little);
  final o = Int64List(n);
  for (var i = 0; i < n; i++) {
    o[i] = bd.getInt64(4 + i * 8, Endian.little);
  }
  return o;
}

void main() {
  test('coarse-pitch mapping matches the Python/RVC oracle exactly', () {
    final pitchf = readF32('$_dir/rvc_pitchf.bin');
    final refCoarse = readI64('$_dir/rvc_pitch.bin');
    final got = rvcCoarsePitch(pitchf);
    expect(got.length, refCoarse.length);
    for (var i = 0; i < refCoarse.length; i++) {
      expect(got[i], refCoarse[i], reason: 'coarse[$i] f0=${pitchf[i]}');
    }
  });

  test('coarse-pitch: unvoiced → 0, monotonic in f0, clamped 1..255', () {
    expect(rvcCoarsePitch(Float32List.fromList([0.0]))[0], 0);
    final c = rvcCoarsePitch(Float32List.fromList([80, 220, 440, 880]));
    for (var i = 1; i < c.length; i++) {
      expect(c[i], greaterThanOrEqualTo(c[i - 1]));
    }
    for (final v in rvcCoarsePitch(Float32List.fromList([10, 5000]))) {
      expect(v, inInclusiveRange(1, 255));
    }
  });

  test('feature alignment 2×-upsamples then trims to the F0 frame count', () {
    // 3 frames × dim 2: [a0,a1, b0,b1, c0,c1]
    final feats = (
      feats: Float32List.fromList([1, 2, 3, 4, 5, 6]),
      frames: 3,
      dim: 2,
    );
    // target 6 frames → each source frame repeated 2×.
    final out = rvcAlignFeatures(feats, 6);
    expect(out, [1, 2, 1, 2, 3, 4, 3, 4, 5, 6, 5, 6]);
    // target 5 → trim the last.
    expect(rvcAlignFeatures(feats, 5), [1, 2, 1, 2, 3, 4, 3, 4, 5, 6]);
  });

  test('RVC model load is licence-gated', () async {
    resetModelLicenseAcceptance();
    final store = RvcModelStore(modelPath: '/nonexistent/rvc.onnx');
    // Not accepted → gate throws BEFORE any file access.
    expect(store.load, throwsA(isA<ModelLicenseNotAccepted>()));
    // Accepted → gets past the gate (then fails on the missing file).
    acceptModelLicense(RvcModelStore.licenseSpdx);
    await expectLater(store.load, throwsA(isA<StateError>()));
    resetModelLicenseAcceptance();
  });

  test(
    'offline conversion runs on a user-supplied RVC model (smoke)',
    () async {
      final path = Platform.environment['COMET_RVC_MODEL'];
      if (path == null || !File(path).existsSync()) {
        // ignore: avoid_print
        print('SKIP: no COMET_RVC_MODEL supplied.');
        return;
      }
      acceptModelLicense(RvcModelStore.licenseSpdx);
      final convert = await RvcModelStore(modelPath: path).converter();
      const t = 100;
      final feats = (
        feats: Float32List(t * 256),
        frames: t,
        dim: 256,
      );
      final f0 = Float32List(t);
      for (var i = 0; i < t; i++) {
        f0[i] = 200.0 + i;
      }
      final res = await convert(feats, f0, 0);
      expect(res.audio.length, greaterThan(0));
      expect(res.audio.every((v) => v.isFinite), isTrue);
      resetModelLicenseAcceptance();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
