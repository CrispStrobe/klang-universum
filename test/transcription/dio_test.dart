// WORLD DIO + StoneMask F0: parity vs pyworld.dio / pyworld.stonemask on a
// deterministic vibrato tone (fixtures from the WORLD reference).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const String _dir = 'test/transcription';

Float64List readF64FromF32(String path) {
  final bd = ByteData.sublistView(File(path).readAsBytesSync());
  final n = bd.getInt32(0, Endian.little);
  final o = Float64List(n);
  for (var i = 0; i < n; i++) {
    o[i] = bd.getFloat32(4 + i * 4, Endian.little);
  }
  return o;
}

/// Max relative error + voiced-agreement over the frames both call voiced.
({double maxRel, double meanRel, int refVoiced, int agree}) compare(
  Float64List got,
  Float64List ref,
) {
  var maxRel = 0.0, sumRel = 0.0, n = 0, refV = 0, agree = 0;
  for (var i = 0; i < ref.length; i++) {
    final rv = ref[i] > 0, gv = got[i] > 0;
    if (rv) refV++;
    if (rv == gv) agree++;
    if (rv && gv) {
      final rel = (got[i] - ref[i]).abs() / ref[i];
      maxRel = math.max(maxRel, rel);
      sumRel += rel;
      n++;
    }
  }
  return (
    maxRel: maxRel,
    meanRel: n > 0 ? sumRel / n : 0,
    refVoiced: refV,
    agree: agree,
  );
}

void main() {
  test('DIO contour matches pyworld.dio', () {
    final x = readF64FromF32('$_dir/dio_input.bin');
    final refF0 = readF64FromF32('$_dir/dio_f0.bin');
    final (f0, _) = dioContour(x);
    expect(f0.length, refF0.length);
    final c = compare(f0, refF0);
    // ignore: avoid_print
    print('DIO: maxRel=${c.maxRel.toStringAsExponential(2)} '
        'meanRel=${c.meanRel.toStringAsExponential(2)} '
        'voiced-agree=${c.agree}/${refF0.length} refVoiced=${c.refVoiced}');
    expect(c.agree, greaterThan((refF0.length * 0.95).toInt()));
    expect(c.meanRel, lessThan(1e-3));
  });

  test('StoneMask refinement matches pyworld.stonemask', () {
    final x = readF64FromF32('$_dir/dio_input.bin');
    final refSm = readF64FromF32('$_dir/dio_stonemask.bin');
    final (f0, tPos) = dioContour(x);
    final sm = stoneMask(x, 16000, tPos, f0);
    final c = compare(sm, refSm);
    // ignore: avoid_print
    print('StoneMask: maxRel=${c.maxRel.toStringAsExponential(2)} '
        'meanRel=${c.meanRel.toStringAsExponential(2)} '
        'voiced-agree=${c.agree}/${refSm.length}');
    expect(c.agree, greaterThan((refSm.length * 0.95).toInt()));
    expect(c.meanRel, lessThan(5e-3));
  });
}
