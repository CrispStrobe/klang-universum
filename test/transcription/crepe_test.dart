// W-CREPE adapter shell. The pure-Dart pre/post-processing — the 360-bin
// activation → f0 decoding, per-frame normalisation, and the bin→Hz mapping — is
// tested here WITHOUT the model, so the only thing left for the model worker is
// to publish the ONNX and confirm the tensor names. A model-gated block
// (skip-if-absent) runs the real inference on a synth A440 once the model lands.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/crepe.dart';
import 'package:comet_beat/core/audio/transcription/crepe_model_store.dart';
import 'package:comet_beat/core/audio/transcription/note_hmm.dart';
import 'package:flutter_test/flutter_test.dart';

// A 360-bin activation with a Gaussian bump centred on [bin].
List<double> _peak(int bin, {double width = 1.5, double height = 0.9}) => [
      for (var i = 0; i < 360; i++)
        height * math.exp(-0.5 * math.pow((i - bin) / width, 2)),
    ];

double _cents(double f, double ref) => 1200 * math.log(f / ref) / math.ln2;

void main() {
  group('decodeActivation (the model-independent decoder)', () {
    test('a peak at a bin decodes to that bin frequency', () {
      const bin = 228; // ≈ A4
      final d = decodeActivation(_peak(bin));
      expect(_cents(d.f0Hz, binToHz(bin)).abs(), lessThan(5));
      expect(d.confidence, closeTo(0.9, 1e-6));
    });

    test('the A4 region really is near 440 Hz', () {
      final d = decodeActivation(_peak(228));
      expect(_cents(d.f0Hz, 440).abs(), lessThan(15));
    });

    test('a flat/empty activation is safe', () {
      expect(decodeActivation(List<double>.filled(360, 0)).f0Hz, 0);
      expect(decodeActivation(const <double>[]).f0Hz, 0);
    });
  });

  group('bin→Hz mapping', () {
    test('spans roughly C1 … ~2 kHz', () {
      expect(binToHz(0), closeTo(31.70, 0.5)); // CREPE bin 0 ≈ 31.7 Hz (~C1)
      expect(binToHz(359), greaterThan(1900));
      expect(binToHz(359), lessThan(2100));
    });
  });

  group('normalizeFrameInto', () {
    test('produces a zero-mean, unit-std frame', () {
      final audio = Float64List(1024);
      for (var i = 0; i < 1024; i++) {
        audio[i] =
            3 + 2 * math.sin(2 * math.pi * 5 * i / 1024); // offset + gain
      }
      final out = Float32List(1024);
      normalizeFrameInto(audio, 0, out);
      var mean = 0.0;
      for (final v in out) {
        mean += v;
      }
      mean /= 1024;
      var varSum = 0.0;
      for (final v in out) {
        varSum += (v - mean) * (v - mean);
      }
      expect(mean.abs(), lessThan(1e-4));
      expect(math.sqrt(varSum / 1024), closeTo(1.0, 1e-3));
    });

    test('a silent frame does not divide by zero', () {
      final out = Float32List(1024);
      normalizeFrameInto(Float64List(1024), 0, out);
      expect(out.every((v) => v == 0), isTrue);
    });
  });

  // Completed once the worker publishes the ONNX (skip-if-absent, no-op in CI).
  group('model-gated real inference', () {
    test('CREPE reads a synth A440 to within a few cents', () async {
      final store = CrepeModelStore();
      if (!store.isPresent()) {
        // No model yet → nothing to verify; the pure decoder above is the lock.
        return;
      }
      final model = await store.load();
      const sr = 16000;
      final mono = Float64List(sr); // 1 s of A4
      for (var i = 0; i < mono.length; i++) {
        mono[i] = 0.5 * math.sin(2 * math.pi * 440 * i / sr);
      }
      final track = await crepeF0(mono, model: model, sampleRate: sr);
      final voiced = track.where((f) => f.f0Hz > 0).toList();
      expect(voiced, isNotEmpty);
      final median =
          (voiced.map((f) => f.f0Hz).toList()..sort())[voiced.length ~/ 2];
      expect(_cents(median, 440).abs(), lessThan(20));
      // …and it flows through the shared note-HMM to a single A4.
      final notes = segmentNotes(track);
      expect(notes.map((n) => n.midi), contains(69));
    });
  });
}
