// Validates the Dart FCPE mel front-end against torchfcpe's MelModule (first
// frames of a known tone). The parity gate for FCPE F0.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/fcpe_mel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Dart FCPE log-mel reproduces torchfcpe MelModule', () {
    final ref = jsonDecode(
      File('test/transcription/fcpe_ref.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final sr = ref['sr'] as int;
    final toneHz = (ref['toneHz'] as num).toDouble();
    final nMel = ref['nMel'] as int;
    final refMel =
        (ref['melFirst3'] as List).map((r) => (r as List).cast<num>()).toList();

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

    final a = FcpeAssets.fromBytes(
      File('test/transcription/fcpe_mel.bin').readAsBytesSync(),
    );
    final (logMel, nFrames) = fcpeLogMel(a, y);

    var maxErr = 0.0;
    for (var t = 0; t < refMel.length; t++) {
      for (var m = 0; m < nMel; m++) {
        final d = (logMel[t * nMel + m] - refMel[t][m].toDouble()).abs();
        if (d > maxErr) maxErr = d;
      }
    }
    // ignore: avoid_print
    print('FCPE mel parity max|Δ| = $maxErr (log-mel), nFrames=$nFrames');
    expect(maxErr, lessThan(0.05));
  });
}
