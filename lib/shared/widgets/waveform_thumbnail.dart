// A tiny centre-line waveform of a mono PCM buffer — for identifying a sample
// by its shape in a list (My Samples, the Sample Extractor). Downsamples to a
// fixed bucket count so painting a long clip stays cheap.

import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Peak amplitudes (0..1) of [pcm] downsampled to [buckets]. Pure + testable.
List<double> waveformPeaks(Float64List pcm, int buckets) {
  final n = buckets < 1 ? 1 : buckets;
  final out = List<double>.filled(n, 0);
  if (pcm.isEmpty) return out;
  for (var b = 0; b < n; b++) {
    final lo = pcm.length * b ~/ n;
    final hi = pcm.length * (b + 1) ~/ n;
    var peak = 0.0;
    for (var i = lo; i < hi; i++) {
      final a = pcm[i].abs();
      if (a > peak) peak = a;
    }
    out[b] = peak > 1 ? 1 : peak;
  }
  return out;
}

/// A fixed-size waveform thumbnail of [pcm].
class WaveformThumbnail extends StatelessWidget {
  const WaveformThumbnail(
    this.pcm, {
    this.width = 44,
    this.height = 28,
    this.color,
    this.buckets = 36,
    super.key,
  });

  final Float64List pcm;
  final double width;
  final double height;
  final Color? color;
  final int buckets;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _WaveformPainter(waveformPeaks(pcm, buckets), c),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter(this.peaks, this.color);
  final List<double> peaks;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;
    final paint = Paint()..color = color;
    final mid = size.height / 2;
    final dx = size.width / peaks.length;
    for (var i = 0; i < peaks.length; i++) {
      final h = (peaks[i] * size.height).clamp(1.0, size.height);
      canvas.drawRect(
        Rect.fromLTWH(i * dx, mid - h / 2, dx <= 1 ? 1 : dx - 0.5, h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      !identical(old.peaks, peaks) || old.color != color;
}
