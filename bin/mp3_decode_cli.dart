// bin/mp3_decode_cli.dart — decode an MP3 to raw PCM16 (s16le) with the
// pure-Dart decoder, so the oracle harness can compare it against ffmpeg/glint.
//
//   dart run bin/mp3_decode_cli.dart in.mp3 out.pcm
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mp3/mp3_decoder.dart';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('usage: mp3_decode_cli in.mp3 out.pcm');
    exit(2);
  }
  final pcm = mp3Decode(File(args[0]).readAsBytesSync());
  final bd = ByteData(pcm.samples.length * 2);
  for (var i = 0; i < pcm.samples.length; i++) {
    var v = (pcm.samples[i].clamp(-1.0, 1.0) * 32767).round();
    v = v.clamp(-32768, 32767);
    bd.setInt16(i * 2, v, Endian.little);
  }
  File(args[1]).writeAsBytesSync(bd.buffer.asUint8List());
  stderr.writeln('decoded ${pcm.samples.length ~/ pcm.channels} frames, '
      '${pcm.channels}ch @ ${pcm.sampleRate}Hz');
}
