// Native CrispASR ggml TabCNN emitter — round-trip through the real GGUF, gated
// on the lib + model being present (COMET_CRISPASR_LIB + a cached
// COMET_TABCNN_GGUF_DIR/tabcnn-f16.gguf). In CI neither is present so
// crispasrFfiTab() returns null and the test skips. Proves acceptance item 3:
// audio → native emissions → decodeTabEmissions, with the GGUF's silent_class
// carried (§2 — native order is 20, not the onnx-remapped 0).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/crispasr_ffi_tab.dart';
import 'package:comet_beat/features/games/composition/tab_emission_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

/// A guitar-like G3 pluck (fundamental + harmonics + decay) — a bare sine reads
/// as silence to the guitar-trained model.
Float64List _pluck({double freq = 196, int sr = 22050, double seconds = 1.0}) {
  final n = (sr * seconds).round();
  const amps = [1.0, 0.6, 0.4, 0.25, 0.15, 0.1];
  final sum = amps.fold<double>(0, (a, b) => a + b);
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    final env = (1 - math.exp(-t / 0.005)) * math.exp(-t / 0.6);
    var s = 0.0;
    for (var k = 0; k < amps.length; k++) {
      s += amps[k] * math.sin(2 * math.pi * freq * (k + 1) * t);
    }
    out[i] = 0.7 * env * s / sum;
  }
  return out;
}

void main() {
  testWidgets('native ggml tab round-trip (COMET_CRISPASR_LIB gated)',
      (tester) async {
    final model = await crispasrFfiTab(); // download:false → cached only
    if (model == null) return; // no lib / GGUF here → skip

    final frames = model.emit(_pluck(), 22050);
    expect(frames, isNotNull);
    expect(frames!.nFrames, greaterThan(0));
    // §2: the native GGUF keeps the upstream class order (silent = 20).
    expect(frames.silentClass, 20);
    expect(frames.logProbs.length, frames.nFrames * kTabStrings * kTabClasses);
    expect(frames.logProbs.every((v) => v.isFinite), isTrue);
    expect(frames.hopSeconds, closeTo(512 / 22050, 1e-6));

    final tab = decodeTabEmissions(frames);
    expect(tab, hasLength(frames.nFrames));
    // The pluck should produce at least one fretted note (0..19), not garbage.
    final frets = tab.expand((f) => f.values).toList();
    expect(frets, isNotEmpty);
    expect(frets.every((f) => f >= 0 && f <= kTabMaxFret), isTrue);

    model.dispose();
  });
}
