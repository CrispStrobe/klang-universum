// The reusable waveform thumbnail: the pure peak downsampler + a render smoke.

import 'dart:typed_data';

import 'package:comet_beat/shared/widgets/waveform_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('waveformPeaks (pure)', () {
    test('downsamples to the requested bucket count', () {
      final pcm = Float64List(1000)..fillRange(0, 1000, 0.5);
      expect(waveformPeaks(pcm, 20).length, 20);
      expect(waveformPeaks(pcm, 20).every((p) => (p - 0.5).abs() < 1e-9), true);
    });

    test('captures the loudest sample in each bucket', () {
      // Two buckets: a quiet half then a loud half.
      final pcm = Float64List(100);
      for (var i = 50; i < 100; i++) {
        pcm[i] = 0.9;
      }
      final peaks = waveformPeaks(pcm, 2);
      expect(peaks[0], 0.0);
      expect(peaks[1], closeTo(0.9, 1e-9));
    });

    test('empty pcm yields all-zero peaks, never throws', () {
      expect(waveformPeaks(Float64List(0), 8), List.filled(8, 0));
    });

    test('clamps out-of-range amplitudes to 1', () {
      final pcm = Float64List.fromList([2.0, -3.0]);
      expect(waveformPeaks(pcm, 1).single, 1.0);
    });
  });

  testWidgets('renders at its fixed size for a non-empty clip', (tester) async {
    final pcm = Float64List(200)..fillRange(0, 200, 0.4);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WaveformThumbnail(pcm)),
      ),
    );
    final size = tester.getSize(find.byType(WaveformThumbnail));
    expect(size.width, 44);
    expect(size.height, 28);
  });
}
