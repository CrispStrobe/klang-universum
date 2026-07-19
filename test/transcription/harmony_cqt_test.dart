// Validates the Dart CQT front-end against a librosa.cqt reference feature — the
// parity gate for BTC chord recognition. Regenerates the fixture's exact tone
// signal, computes the CQT, and asserts the normalized log-feature matches
// librosa frame-for-frame.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/harmony_cqt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Dart CQT reproduces the librosa.cqt BTC feature', () {
    final ref = jsonDecode(
      File('test/transcription/btc_cqt_ref.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final sr = ref['sr'] as int;
    final tones =
        (ref['tones'] as List).cast<num>().map((e) => e.toDouble()).toList();
    final dur = (ref['dur'] as num).toDouble();
    final nBins = ref['nBins'] as int;
    final refFeat =
        (ref['feature'] as List).map((r) => (r as List).cast<num>()).toList();

    // Regenerate the exact fixture signal: sum of 0.3·sin tones at 22.05 kHz.
    final n = (sr * dur).round();
    final y = Float64List(n);
    for (var i = 0; i < n; i++) {
      var s = 0.0;
      for (final f in tones) {
        s += 0.3 * sin(2 * pi * f * i / sr);
      }
      y[i] = s;
    }

    final fb = CqtFilterBank.fromBytes(
      File('test/transcription/btc_cqt.bin').readAsBytesSync(),
    );
    final (feat, nFrames) = btcCqtFeature(fb, y);

    expect(nFrames, refFeat.length);
    var maxErr = 0.0;
    for (var t = 0; t < nFrames; t++) {
      for (var k = 0; k < nBins; k++) {
        final d = (feat[t * nBins + k] - refFeat[t][k].toDouble()).abs();
        if (d > maxErr) maxErr = d;
      }
    }
    // ignore: avoid_print
    print('CQT parity max|Δ| = $maxErr (normalized feature units)');
    expect(maxErr, lessThan(0.02));
  });
}
