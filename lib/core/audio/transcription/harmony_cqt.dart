// lib/core/audio/transcription/harmony_cqt.dart
//
// Constant-Q transform front-end for BTC chord recognition — reproduces the
// `log(|librosa.cqt| + 1e-6)` (globally normalised) feature BTC was trained on.
//
// librosa.cqt's per-octave soxr downsampling is a speed optimisation of a single
// complex filterbank applied to a boxcar STFT (`fft_basis @ STFT`); that direct
// form matches librosa.cqt at cosine ~1.0 and gives BTC identical chords. We
// ship the exact complex filterbank (from librosa, banded/sparse — each CQT
// filter is frequency-local) as a compact asset and apply it here with the app's
// radix-2 FFT.
//
// WEB-SAFE: pure Dart (the app FFT + `dart:typed_data`); the filterbank arrives
// as bytes (the native store downloads it). No dart:io.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/chroma_analysis.dart' show fft;

/// The precomputed CQT complex filterbank (banded) + BTC's global log-feature
/// normalisation, parsed from the `btc-cqt.bin` asset.
class CqtFilterBank {
  CqtFilterBank({
    required this.nBins,
    required this.nFft,
    required this.hop,
    required this.mean,
    required this.std,
    required this.lengths,
    required this.lo,
    required this.hi,
    required this.off,
    required this.re,
    required this.im,
  });

  final int nBins; // 144
  final int nFft; // 32768
  final int hop; // 2048
  final double mean; // global log-feature mean
  final double std; // global log-feature std
  final Float32List lengths; // [nBins] — magnitude scale (÷√length)
  final Int32List lo; // [nBins] band start freq bin
  final Int32List hi; // [nBins] band end (exclusive)
  final Int32List off; // [nBins] offset into re/im for each band
  final Float32List re; // concatenated band real parts
  final Float32List im; // concatenated band imag parts

  /// Parse the little-endian asset:
  /// `int32[4]{nBins,nFft,nFreq,hop} · float32[2]{mean,std} · float32[nBins]lengths`
  /// `· int32[nBins]lo · int32[nBins]hi · float32[Σband]re · float32[Σband]im`.
  factory CqtFilterBank.fromBytes(Uint8List bytes) {
    final d = ByteData.sublistView(bytes);
    var p = 0;
    int i32() {
      final v = d.getInt32(p, Endian.little);
      p += 4;
      return v;
    }

    double f32() {
      final v = d.getFloat32(p, Endian.little);
      p += 4;
      return v;
    }

    final nBins = i32();
    final nFft = i32();
    i32(); // nFreq (unused; hi bounds are already < nFreq)
    final hop = i32();
    final mean = f32();
    final std = f32();
    final lengths = Float32List(nBins);
    for (var k = 0; k < nBins; k++) {
      lengths[k] = f32();
    }
    final lo = Int32List(nBins), hi = Int32List(nBins), off = Int32List(nBins);
    for (var k = 0; k < nBins; k++) {
      lo[k] = i32();
    }
    for (var k = 0; k < nBins; k++) {
      hi[k] = i32();
    }
    var total = 0;
    for (var k = 0; k < nBins; k++) {
      off[k] = total;
      total += hi[k] - lo[k];
    }
    final re = Float32List(total), im = Float32List(total);
    for (var j = 0; j < total; j++) {
      re[j] = f32();
    }
    for (var j = 0; j < total; j++) {
      im[j] = f32();
    }
    return CqtFilterBank(
      nBins: nBins,
      nFft: nFft,
      hop: hop,
      mean: mean,
      std: std,
      lengths: lengths,
      lo: lo,
      hi: hi,
      off: off,
      re: re,
      im: im,
    );
  }
}

/// Compute the BTC CQT feature for [audio22k] (mono, 22050 Hz). Returns
/// `(feature, nFrames)` where feature is row-major `[nFrames × nBins]`, already
/// `log(|CQT|+1e-6)` and globally `(·-mean)/std`-normalised — ready to segment
/// into 108-frame windows for the model.
(Float32List, int) btcCqtFeature(CqtFilterBank fb, Float64List audio22k) {
  final nFft = fb.nFft, hop = fb.hop, nBins = fb.nBins;
  final half = nFft ~/ 2;
  // librosa.stft centers: pad nFft/2 each side (zeros), frame at hop.
  final padded = Float64List(audio22k.length + nFft)
    ..setRange(half, half + audio22k.length, audio22k);
  final nFrames = 1 + audio22k.length ~/ hop;
  final feat = Float32List(nFrames * nBins);
  final re = Float64List(nFft), im = Float64List(nFft);
  const eps = 1e-6;
  for (var t = 0; t < nFrames; t++) {
    final start = t * hop;
    for (var i = 0; i < nFft; i++) {
      re[i] = padded[start + i];
      im[i] = 0.0;
    }
    fft(re, im); // in-place radix-2, unscaled (matches numpy.fft)
    final base = t * nBins;
    for (var k = 0; k < nBins; k++) {
      final lo = fb.lo[k], hi = fb.hi[k], o = fb.off[k];
      var sr = 0.0, si = 0.0;
      for (var f = lo; f < hi; f++) {
        final br = fb.re[o + f - lo], bi = fb.im[o + f - lo];
        final dr = re[f], di = im[f];
        sr += br * dr - bi * di;
        si += br * di + bi * dr;
      }
      final mag = math.sqrt(sr * sr + si * si) / math.sqrt(fb.lengths[k]);
      feat[base + k] = (math.log(mag + eps) - fb.mean) / fb.std;
    }
  }
  return (feat, nFrames);
}
