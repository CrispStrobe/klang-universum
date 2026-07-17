// AECMOS eval smoke test — proves the copied `MelFrontEnd` + `AecmosScorer`
// wiring compiles and runs inside mus. The DSP itself is exhaustively verified
// upstream in onnx_runtime_dart (mel front-end matched to librosa at 2.4e-7, MOS
// to ~1e-6 vs the Python reference), so here we only guard the mus-side
// integration: the model-free front-end yields finite, correctly-shaped features,
// and the scorer rejects an unrecognized model up front. Full scoring needs a
// user-provided Microsoft AEC-Challenge model, so it runs via bin/aecmos.dart,
// not in CI.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../bin/aecmos/aecmos_scorer.dart';
import '../bin/aecmos/mel_spectrogram.dart';

void main() {
  test('the AECMOS mel front-end yields finite, correctly-shaped features', () {
    // Half a second of a 16 kHz tone at the 16k AECMOS config: nFft 513
    // (dftSize + 1, the odd length AECMOS uses), hop 256, 160 mel bands.
    const sr = 16000, nFft = 513, hop = 256, nMels = 160;
    final signal = Float32List(sr ~/ 2);
    for (var i = 0; i < signal.length; i++) {
      signal[i] = 0.2 * math.sin(2 * math.pi * 440 * i / sr);
    }

    // nMels defaults to 160 (the AECMOS band count), so it's left implicit.
    final feats = aecmosMelFeatures(signal, sr: sr, nFft: nFft, hopLength: hop);
    final frames = melFrameCount(signal.length, nFft, hop);
    expect(frames, greaterThan(0));
    expect(feats.length, frames * nMels, reason: '[frames x nMels] row-major');
    expect(feats.every((v) => v.isFinite), isTrue);
  });

  test('AecmosScorer rejects a path with no known AECMOS run id', () {
    // The factory keys config off the run id in the path and throws before it
    // ever touches the filesystem, so this needs no model file.
    expect(
      () => AecmosScorer('not-a-real-aecmos-model.onnx'),
      throwsArgumentError,
    );
  });
}
