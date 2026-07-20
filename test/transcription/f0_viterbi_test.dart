// Viterbi pitch-path decoding: exact parity vs librosa.sequence.viterbi /
// torchcrepe on a synthetic 360-bin activation lattice (with a decoy octave
// spike that argmax follows but Viterbi smooths).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/crepe.dart';
import 'package:comet_beat/core/audio/transcription/f0_viterbi.dart';
import 'package:flutter_test/flutter_test.dart';

const String _dir = 'test/transcription';

Float64List readF32(String path) {
  final bd = ByteData.sublistView(File(path).readAsBytesSync());
  final n = bd.getInt32(0, Endian.little);
  final o = Float64List(n);
  for (var i = 0; i < n; i++) {
    o[i] = bd.getFloat32(4 + i * 4, Endian.little);
  }
  return o;
}

Int32List readI32(String path) {
  final bd = ByteData.sublistView(File(path).readAsBytesSync());
  final n = bd.getInt32(0, Endian.little);
  final o = Int32List(n);
  for (var i = 0; i < n; i++) {
    o[i] = bd.getInt32(4 + i * 4, Endian.little);
  }
  return o;
}

void main() {
  const frames = 100, bins = 360;

  test('viterbiPitchPath is bit-identical to librosa.sequence.viterbi', () {
    final acts = readF32('$_dir/vit_acts.bin');
    final refPath = readI32('$_dir/vit_path.bin');
    final got = viterbiPitchPath(acts, frames, bins);
    expect(got.length, frames);
    for (var t = 0; t < frames; t++) {
      expect(got[t], refPath[t], reason: 'path[$t]');
    }
  });

  test('Viterbi smooths a decoy octave spike that argmax would follow', () {
    final acts = readF32('$_dir/vit_acts.bin');
    final path = viterbiPitchPath(acts, frames, bins);
    // argmax path for comparison
    final argmax = Int32List(frames);
    for (var t = 0; t < frames; t++) {
      var best = double.negativeInfinity, arg = 0;
      for (var b = 0; b < bins; b++) {
        if (acts[t * bins + b] > best) {
          best = acts[t * bins + b];
          arg = b;
        }
      }
      argmax[t] = arg;
    }
    var diff = 0;
    for (var t = 0; t < frames; t++) {
      if (path[t] != argmax[t]) diff++;
    }
    expect(diff, greaterThan(0), reason: 'Viterbi should differ from argmax');
    // No frame-to-frame jump exceeds the transition band (±11).
    for (var t = 1; t < frames; t++) {
      expect((path[t] - path[t - 1]).abs(), lessThanOrEqualTo(11));
    }
  });

  test('CREPE viterbi decode is smoother than argmax on the decoy', () {
    final acts = Float32List.fromList(readF32('$_dir/vit_acts.bin'));
    final arg = decodeCrepeActivation(acts, frames);
    final vit = decodeCrepeActivationViterbi(acts, frames);
    expect(vit.length, frames);
    // Max frame-to-frame f0 jump (in cents): viterbi must be much smoother than
    // argmax, which follows the octave decoy for a few frames.
    double maxJumpCents(List<(double, double)> tr) {
      var mx = 0.0;
      for (var t = 1; t < tr.length; t++) {
        final a = tr[t].$1, b = tr[t - 1].$1;
        if (a > 0 && b > 0) {
          final j = (1200 * (math.log(a / b) / math.ln2)).abs();
          if (j > mx) mx = j;
        }
      }
      return mx;
    }

    expect(
      maxJumpCents(vit),
      lessThan(maxJumpCents(arg)),
      reason: 'viterbi should smooth the octave decoy',
    );
    // The argmax decode jumps hard (the decoy is ~60 bins ≈ 1200 cents away).
    expect(maxJumpCents(arg), greaterThan(600));
  });
}
