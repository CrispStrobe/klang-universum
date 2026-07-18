// bin/gen_mdct.dart — dump a granule's mdct_flat[576] (band-major, post-alias)
// for the MP3 quantizer A/B. Runs the app's OWN subband+MDCT (proven
// machine-equivalent to glint) over a chosen signal, warms up the overlap
// state, and writes the target granule's 576 coefficients (one per line) so
// glint_quant and the Dart quantizer see byte-identical input.
//
//   dart run bin/gen_mdct.dart <signal> <out.txt>
//   signal ∈ { noise, tone, speech, chord }
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mp3/mp3_mdct.dart';
import 'package:comet_beat/core/audio/mp3/mp3_subband.dart';

double _sample(String sig, int n, int i) {
  final t = i / 44100.0;
  switch (sig) {
    case 'noise':
      // LCG white noise (flat spectrum): masking loop leaves sf all-zero.
      var s = (0x12345 + i * 2654435761) & 0xFFFFFFFF;
      s = (s * 1664525 + 1013904223) & 0xFFFFFFFF;
      return ((s >> 8) & 0xFFFF) / 65536.0 * 2 - 1;
    case 'tone':
      return 0.7 * math.sin(2 * math.pi * 440 * t);
    case 'chord':
      return 0.3 *
          (math.sin(2 * math.pi * 261.63 * t) +
              math.sin(2 * math.pi * 329.63 * t) +
              math.sin(2 * math.pi * 392.0 * t));
    case 'speech':
    default:
      // Broadband tonal (glint's speech-like voiced harmonics + HF sizzle +
      // deterministic pseudo-noise): the case where zero-scalefactor coding
      // audibly fails, so it exercises the NMR shaping loop.
      final env = 0.35 +
          0.65 *
              (0.5 + 0.5 * math.sin(2 * math.pi * 2.7 * t)) *
              (0.7 + 0.3 * math.sin(2 * math.pi * 5.3 * t + 0.4));
      var voiced = 0.0;
      for (var h = 0; h < 12; h++) {
        voiced += (1.0 / (h + 1)) *
            math.sin(2 * math.pi * 155 * (h + 1) * t + h * 0.37);
      }
      var s = (0x1234 + i * 22695477) & 0xFFFFFFFF;
      s = (s * 1103515245 + 12345) & 0xFFFFFFFF;
      final noise = ((s >> 9) & 0x7FFF) / 32768.0 * 2 - 1;
      var v = (voiced * 0.12 + noise * 0.035) * env;
      v += 0.018 *
          math.sin(2 * math.pi * 4200 * t) *
          (0.5 + 0.5 * math.sin(2 * math.pi * 3.1 * t));
      return v * 0.82;
  }
}

void main(List<String> args) {
  final sig = args.isNotEmpty ? args[0] : 'speech';
  final out = args.length > 1 ? args[1] : 'mdct_$sig.txt';
  const target = 40; // a mid-stream granule (overlap state settled by here)

  final sb = Mp3SubbandAnalysis();
  final mdct = Mp3Mdct();
  final subband = Float64List(576);
  final mdctBuf = Float64List(576);
  final slot = Float64List(32);
  final so = Float64List(32);

  var sampleIdx = 0;
  Float64List? captured;
  for (var g = 0; g <= target; g++) {
    for (var ts = 0; ts < 18; ts++) {
      for (var i = 0; i < 32; i++) {
        slot[i] = _sample(sig, g, sampleIdx++);
      }
      sb.processSlot(slot, so);
      for (var b = 0; b < 32; b++) {
        subband[b * 18 + ts] = so[b];
      }
    }
    mdct.process(subband, mdctBuf);
    mdct.aliasReduce(mdctBuf);
    if (g == target) captured = Float64List.fromList(mdctBuf);
  }

  final buf = StringBuffer();
  for (final v in captured!) {
    buf.writeln(v.toStringAsExponential(17));
  }
  File(out).writeAsStringSync(buf.toString());
  final nz = captured.where((v) => v.abs() > 1e-9).length;
  stderr.writeln('wrote $out  ($sig, granule $target, $nz/576 nonzero coeffs)');
}
