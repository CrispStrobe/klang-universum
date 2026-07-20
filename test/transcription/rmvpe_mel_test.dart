// Validates the Dart RMVPE mel front-end against the RVC MelSpectrogram
// reference (first frames of a known tone). The parity gate for RMVPE F0.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/rmvpe_mel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Dart log-mel reproduces the RVC MelSpectrogram', () {
    final ref = jsonDecode(
      File('test/transcription/rmvpe_ref.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final sr = ref['sr'] as int;
    final toneHz = (ref['toneHz'] as num).toDouble();
    final nMel = ref['nMel'] as int;
    // melFirst3Frames[frame][mel] — the reference log-mel for frames 0..2.
    final refMel = (ref['melFirst3Frames'] as List)
        .map((r) => (r as List).cast<num>())
        .toList();

    // Regenerate the exact fixture tone: 5-harmonic 220 Hz, peak-normalised.
    final n = (sr * 1.2).round();
    final y = Float64List(n);
    var peak = 0.0;
    for (var i = 0; i < n; i++) {
      var s = 0.0;
      for (var k = 1; k <= 5; k++) {
        s += (1.0 / k) * sin(2 * pi * k * toneHz * i / sr);
      }
      y[i] = s;
      if (s.abs() > peak) peak = s.abs();
    }
    for (var i = 0; i < n; i++) {
      y[i] /= peak;
    }

    final mb = RmvpeMel.fromBytes(
      File('test/transcription/rmvpe_mel.bin').readAsBytesSync(),
    );
    final (logMel, nFrames) = rmvpeLogMel(mb, y);

    var maxErr = 0.0;
    for (var t = 0; t < refMel.length; t++) {
      for (var m = 0; m < nMel; m++) {
        // logMel is mel-major: [m * nFrames + t].
        final d = (logMel[m * nFrames + t] - refMel[t][m].toDouble()).abs();
        if (d > maxErr) maxErr = d;
      }
    }
    // ignore: avoid_print
    print('RMVPE mel parity max|Δ| = $maxErr (log-mel units)');
    expect(maxErr, lessThan(0.05));
  });
}
