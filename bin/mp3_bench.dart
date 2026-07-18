// bin/mp3_bench.dart
//
// Quality + speed harness for the pure-Dart MP3 encoder DSP front-end vs glint.
// Runs the SAME deterministic LCG input as scratchpad/glint_ref.cpp through the
// Dart subband filter + MDCT + alias reduction, compares against glint's dumped
// reference (bit-exactness), and benchmarks throughput.
//
//   dart run bin/mp3_bench.dart <glint_ref.txt> [granules]
//
// glint's numbers come from: cc -O3 -march=native glint_ref.cpp libglint.a.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mp3/mp3_mdct.dart';
import 'package:comet_beat/core/audio/mp3/mp3_subband.dart';

// The exact LCG from glint_ref.cpp; glint rounds each sample to float32, so we
// do too (round-trip through a Float32List) to feed identical inputs.
class _Lcg {
  int _s = 0x12345;
  final Float32List _f = Float32List(1);
  double next() {
    _s = (_s * 1664525 + 1013904223) & 0xFFFFFFFF;
    final d = (((_s >> 8) & 0xFFFF) / 65536.0) * 2.0 - 1.0;
    _f[0] = d; // round to float32 like glint's (float)
    return _f[0];
  }
}

// One granule (18 slots × 32 samples) through subband → mdct → alias.
void _granule(_Lcg lcg, Mp3SubbandAnalysis sb, Mp3Mdct mdct,
    Float64List subband, Float64List mdctOut) {
  final slot = Float64List(32);
  final out = Float64List(32);
  for (var ts = 0; ts < 18; ts++) {
    for (var i = 0; i < 32; i++) {
      slot[i] = lcg.next();
    }
    sb.processSlot(slot, out);
    for (var b = 0; b < 32; b++) {
      subband[b * 18 + ts] = out[b];
    }
  }
  mdct.process(subband, mdctOut);
  mdct.aliasReduce(mdctOut);
}

void main(List<String> args) {
  final refPath = args.isNotEmpty ? args[0] : 'glint_ref.txt';
  final benchG = args.length > 1 ? int.parse(args[1]) : 20000;

  final sb = Mp3SubbandAnalysis();
  final mdct = Mp3Mdct();
  final subband = Float64List(32 * 18);
  final mdctOut = Float64List(32 * 18);

  // --- correctness: 5 warmup granules, dump granule 5 (matches the C++) ---
  final lcg = _Lcg();
  for (var g = 0; g < 5; g++) {
    _granule(lcg, sb, mdct, subband, mdctOut);
  }
  _granule(lcg, sb, mdct, subband, mdctOut);

  final ref = File(refPath)
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .map(double.parse)
      .toList();
  var maxSb = 0.0, maxMdct = 0.0, maxScale = 0.0;
  for (var i = 0; i < 576; i++) {
    maxSb = _max(maxSb, (subband[i] - ref[i]).abs());
    maxMdct = _max(maxMdct, (mdctOut[i] - ref[576 + i]).abs());
    maxScale = _max(maxScale, ref[i].abs());
    maxScale = _max(maxScale, ref[576 + i].abs());
  }

  // --- benchmark ---
  sb.reset();
  mdct.reset();
  final lcg2 = _Lcg();
  final sw = Stopwatch()..start();
  var acc = 0.0;
  for (var g = 0; g < benchG; g++) {
    _granule(lcg2, sb, mdct, subband, mdctOut);
    acc += mdctOut[0];
  }
  sw.stop();
  final perSec = benchG / (sw.elapsedMicroseconds / 1e6);

  stdout.writeln('MP3 DSP front-end — Dart vs glint');
  stdout.writeln('  subband max abs error : ${maxSb.toStringAsExponential(3)}');
  stdout
      .writeln('  mdct    max abs error : ${maxMdct.toStringAsExponential(3)}');
  stdout.writeln('  (signal peak ~${maxScale.toStringAsFixed(2)} => '
      'relative ~${(_max(maxSb, maxMdct) / maxScale).toStringAsExponential(2)})');
  stdout.writeln('  bit-exact vs glint    : '
      '${maxSb == 0 && maxMdct == 0 ? "YES" : "no (float-rounding; see below)"}');
  stdout.writeln('  Dart throughput       : '
      '${perSec.toStringAsFixed(0)} granules/s  '
      '($benchG granules in ${sw.elapsedMilliseconds} ms, acc=${acc.toStringAsFixed(3)})');
}

double _max(double a, double b) => a > b ? a : b;
