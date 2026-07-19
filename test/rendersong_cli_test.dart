// bin/rendersong.dart end-to-end: parse a notation file → render every note
// through a voice → write audio. Runs the real CLI as a subprocess with the
// built-in voice (no SoundFont, so no network / glint needed), asserting a
// valid, non-trivial WAV and MP3 come out. The pitch-correctness of the render
// is covered by the render-→-detect acceptance in the repo's listen.dart flow.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _abc = '''
X:1
T:Scale
M:4/4
L:1/4
K:C
C D E F | G A B c |
''';

Future<ProcessResult> _render(String input, String output) => Process.run(
      'dart',
      ['run', 'bin/rendersong.dart', input, output],
    );

void main() {
  late Directory dir;
  late String abc;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('rendersong_test');
    abc = '${dir.path}/scale.abc';
    File(abc).writeAsStringSync(_abc);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'ABC → WAV: a real RIFF file with audio',
    () async {
      final out = '${dir.path}/scale.wav';
      final r = await _render(abc, out);
      expect(r.exitCode, 0, reason: 'stderr: ${r.stderr}');
      final bytes = File(out).readAsBytesSync();
      // RIFF header + more than just the 44-byte WAV header of silence.
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(bytes.length, greaterThan(100000));
    },
    timeout: const Timeout(
      Duration(minutes: 3),
    ),
  );

  test(
    'ABC → MP3: a valid MP3 frame',
    () async {
      final out = '${dir.path}/scale.mp3';
      final r = await _render(abc, out);
      expect(r.exitCode, 0, reason: 'stderr: ${r.stderr}');
      final bytes = File(out).readAsBytesSync();
      // MP3 starts with an ID3 tag or an MPEG frame sync (0xFFEx/0xFFFx).
      final isId3 = bytes.length >= 3 &&
          bytes[0] == 0x49 &&
          bytes[1] == 0x44 &&
          bytes[2] == 0x33;
      final isFrameSync =
          bytes.length >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0;
      expect(isId3 || isFrameSync, isTrue, reason: 'not an MP3 stream');
      expect(bytes.length, greaterThan(20000));
    },
    timeout: const Timeout(
      Duration(minutes: 3),
    ),
  );

  test(
    'an unknown output extension fails cleanly',
    () async {
      final r = await _render(abc, '${dir.path}/x.ogg');
      expect(r.exitCode, isNot(0));
      expect(r.stderr.toString(), contains('.wav'));
    },
    timeout: const Timeout(
      Duration(minutes: 3),
    ),
  );

  test(
    '--bits 24 (+ chorus) writes a 24-bit WAV',
    () async {
      final out = '${dir.path}/w24.wav';
      final r = await Process.run(
        'dart',
        [
          'run',
          'bin/rendersong.dart',
          abc,
          out,
          '--bits',
          '24',
          '--chorus',
          '0.3',
        ],
      );
      expect(r.exitCode, 0, reason: 'stderr: ${r.stderr}');
      final b = File(out).readAsBytesSync();
      expect(b[34], 24, reason: 'bitsPerSample field = 24');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    '--play with no output renders + plays a temp (seam-skipped)',
    () async {
      // COMET_RENDERSONG_NOPLAY skips the real player, so CI stays silent.
      final r = await Process.run(
        'dart',
        ['run', 'bin/rendersong.dart', abc, '--play'],
        environment: {'COMET_RENDERSONG_NOPLAY': '1'},
      );
      expect(r.exitCode, 0, reason: 'stderr: ${r.stderr}');
      expect(r.stderr.toString(), contains('playing'));
    },
    timeout: const Timeout(
      Duration(minutes: 3),
    ),
  );
}
