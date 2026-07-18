// bin/mp3_encode_cli.dart
//
// A tiny CLI wrapper around the pure-Dart MP3 encoder, matching enough of
// glint_cli's interface (`input.wav output.mp3 -b BITRATE`) that glint's OWN
// benchmark/quality harness (tests/measure_audio.py) can drive it side-by-side
// with glint_cli. Mono only (our first-cut encoder), so it always mono-mixes.
// Prints `Speed: Nx realtime` on stderr in glint's format.
//
//   dart run bin/mp3_encode_cli.dart in.wav out.mp3 -b 128
import 'dart:io';

import 'package:comet_beat/core/audio/mp3/mp3_encoder.dart';
import 'package:comet_beat/core/audio/wav_io.dart';

void main(List<String> args) {
  final pos = <String>[];
  var bitrate = 128;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '-b') {
      bitrate = int.parse(args[++i]);
    } else if (a == '-m' || a == '-q' || a == '-p' || a == '-s' || a == '-V') {
      i++; // consume + ignore (mono-only, single quality)
    } else if (!a.startsWith('-')) {
      pos.add(a);
    }
  }
  if (pos.length < 2) {
    stderr.writeln('usage: mp3_encode_cli in.wav out.mp3 [-b kbps]');
    exit(2);
  }

  final wav = readWavPcm16(File(pos[0]).readAsBytesSync());
  final pcm = wavToMonoFloat(wav);
  final seconds = pcm.length / wav.sampleRate;

  final sw = Stopwatch()..start();
  final mp3 = mp3EncodeMono(pcm, sampleRate: wav.sampleRate, bitrate: bitrate);
  sw.stop();

  File(pos[1]).writeAsBytesSync(mp3);
  final secs = sw.elapsedMicroseconds / 1e6;
  final speed = secs > 0 ? seconds / secs : 0.0;
  stderr.writeln('Input: ${wav.sampleRate} Hz, ${wav.channels} channel(s)');
  stderr.writeln('Done: ${pcm.length} samples, ${mp3.length} bytes written');
  stderr.writeln('Speed: ${speed.toStringAsFixed(1)}x realtime '
      '(${seconds.toStringAsFixed(2)} sec audio in '
      '${secs.toStringAsFixed(2)} sec)');
}
