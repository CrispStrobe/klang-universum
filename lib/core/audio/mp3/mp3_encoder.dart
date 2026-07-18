// lib/core/audio/mp3/mp3_encoder.dart
//
// Top-level pure-Dart MP3 encoder — slice 5c/6 of the port. Assembles a
// complete, decodable MPEG-1 Layer III (mono) CBR stream from PCM: per granule
// runs subband → MDCT → alias → a rate-control loop that picks global_gain so
// the Huffman data fits the frame budget → side-info + Huffman main data. This
// first cut uses zero scalefactors (global_gain only) and no bit reservoir
// (main_data_begin = 0) — valid MP3, simpler than glint's reservoir path.
// Pure Dart => runs identically on native AND web.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mp3/mp3_bitstream.dart';
import 'package:comet_beat/core/audio/mp3/mp3_frame.dart';
import 'package:comet_beat/core/audio/mp3/mp3_granule.dart';
import 'package:comet_beat/core/audio/mp3/mp3_mdct.dart';
import 'package:comet_beat/core/audio/mp3/mp3_quantize.dart';
import 'package:comet_beat/core/audio/mp3/mp3_subband.dart';

/// Mono side-info size for MPEG-1 Layer III: 17 bytes.
const int _kMonoSideInfoBytes = 17;

/// Encode mono [pcm] (−1..1) to an MPEG-1 Layer III (mono, CBR) `.mp3`.
/// [bitrate] kbps must be a valid MPEG-1 rate; [sampleRate] one of 44100/48000/
/// 32000.
Uint8List mp3EncodeMono(
  Float64List pcm, {
  int sampleRate = 44100,
  int bitrate = 128,
}) {
  final srIndex = mp3SampleRateIndex(sampleRate);
  if (srIndex < 0) {
    throw ArgumentError('unsupported sample rate: $sampleRate');
  }
  if (mp3BitrateIndex(bitrate) == 0) {
    throw ArgumentError('unsupported bitrate: $bitrate');
  }

  final sb = Mp3SubbandAnalysis();
  final mdct = Mp3Mdct();
  final subband = Float64List(576);
  final mdctBuf = Float64List(576);
  final slot = Float64List(32);
  final so = Float64List(32);
  final out = BytesBuilder(copy: false);

  final brBps = bitrate * 1000;
  final frameBase = 144 * brBps ~/ sampleRate;
  final rem = (144 * brBps) % sampleRate;
  var padAcc = 0;

  var pos = 0;
  while (pos < pcm.length) {
    // Padding bit averages the bitrate across frames (fractional frame size).
    padAcc += rem;
    final pad = padAcc >= sampleRate;
    if (pad) padAcc -= sampleRate;
    final frameSize = frameBase + (pad ? 1 : 0);
    final availTotal = (frameSize - 4 - _kMonoSideInfoBytes) * 8;
    final availPer = availTotal ~/ 2;

    final grIx = <Int16List>[];
    final grRegions = <Mp3HuffRegions>[];
    final grGain = <int>[];
    final grBits = <int>[];

    for (var g = 0; g < 2; g++) {
      for (var ts = 0; ts < 18; ts++) {
        for (var i = 0; i < 32; i++) {
          final idx = pos + g * 576 + ts * 32 + i;
          slot[i] = idx < pcm.length ? pcm[idx] : 0.0;
        }
        sb.processSlot(slot, so);
        for (var b = 0; b < 32; b++) {
          subband[b * 18 + ts] = so[b];
        }
      }
      mdct.process(subband, mdctBuf);
      mdct.aliasReduce(mdctBuf);
      final fit = _fitGain(mdctBuf, srIndex, availPer);
      grIx.add(fit.ix);
      grRegions.add(fit.regions);
      grGain.add(fit.gain);
      grBits.add(fit.bits);
    }

    final frame = Mp3BitWriter();
    _writeHeader(frame, bitrate, sampleRate, pad);
    // Side info (mono): main_data_begin + private + scfsi + 2 granules.
    frame.writeBits(0, 9); // main_data_begin (no reservoir)
    frame.writeBits(0, 5); // private bits (mono)
    frame.writeBits(0, 4); // scfsi
    for (var g = 0; g < 2; g++) {
      _writeGranuleSideInfo(frame, grRegions[g], grGain[g], grBits[g]);
    }
    // Main data: 2 granules of Huffman (scalefactors are all zero → no bits).
    for (var g = 0; g < 2; g++) {
      mp3EncodeGranule(frame, grIx[g], grRegions[g], srIndex);
    }
    frame.byteAlign();
    final bytes = frame.takeBytes();
    out.add(bytes);
    if (bytes.length < frameSize) {
      out.add(Uint8List(frameSize - bytes.length)); // pad the frame
    }
    pos += 1152;
  }
  return out.toBytes();
}

class _Fit {
  _Fit(this.gain, this.ix, this.regions, this.bits);
  final int gain;
  final Int16List ix;
  final Mp3HuffRegions regions;
  final int bits;
}

int _granuleBits(Int16List ix, Mp3HuffRegions r, int srIndex) {
  final w = Mp3BitWriter();
  mp3EncodeGranule(w, ix, r, srIndex);
  return w.bitCount;
}

/// Binary-search the SMALLEST global_gain (finest quantization) whose Huffman
/// data fits [avail] bits — best quality within budget.
_Fit _fitGain(Float64List mdct, int srIndex, int avail) {
  var lo = 0, hi = 255, ansGain = 255;
  Int16List? ansIx;
  Mp3HuffRegions? ansReg;
  var ansBits = 0;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final ix = mp3QuantizeUniform(mdct, mid);
    final regions = mp3ComputeRegions(ix, srIndex);
    final bits = _granuleBits(ix, regions, srIndex);
    if (bits <= avail) {
      ansGain = mid;
      ansIx = ix;
      ansReg = regions;
      ansBits = bits;
      hi = mid - 1; // try finer
    } else {
      lo = mid + 1; // coarser
    }
  }
  ansIx ??= mp3QuantizeUniform(mdct, 255);
  ansReg ??= mp3ComputeRegions(ansIx, srIndex);
  ansBits = _granuleBits(ansIx, ansReg, srIndex);
  return _Fit(ansGain, ansIx, ansReg, ansBits);
}

void _writeHeader(Mp3BitWriter w, int bitrate, int sampleRate, bool pad) {
  w
    ..writeBits(0x7FF, 11)
    ..writeBits(0x3, 2) // MPEG-1
    ..writeBits(0x1, 2) // Layer III
    ..writeBits(1, 1) // no CRC
    ..writeBits(mp3BitrateIndex(bitrate), 4)
    ..writeBits(mp3SampleRateIndex(sampleRate), 2)
    ..writeBits(pad ? 1 : 0, 1)
    ..writeBits(0, 1) // private
    ..writeBits(Mp3ChannelMode.mono.index, 2)
    ..writeBits(0, 2) // mode extension
    ..writeBits(0, 1) // copyright
    ..writeBits(1, 1) // original
    ..writeBits(0, 2); // emphasis
}

/// glint's `write_granule_side_info`, block_type 0 (long), zero scalefactors.
void _writeGranuleSideInfo(
  Mp3BitWriter w,
  Mp3HuffRegions r,
  int globalGain,
  int part23Length,
) {
  w
    ..writeBits(part23Length, 12)
    ..writeBits(r.bigValues, 9)
    ..writeBits(globalGain, 8)
    ..writeBits(0, 4) // scalefac_compress = 0 (slen1=slen2=0 → no sf bits)
    ..writeBits(0, 1) // window_switching_flag = 0
    ..writeBits(r.tableSelect[0], 5)
    ..writeBits(r.tableSelect[1], 5)
    ..writeBits(r.tableSelect[2], 5)
    ..writeBits(r.region0Count, 4)
    ..writeBits(r.region1Count, 3)
    ..writeBits(0, 1) // preflag
    ..writeBits(0, 1) // scalefac_scale
    ..writeBits(r.count1Table, 1);
}
