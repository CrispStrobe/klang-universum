// bin/rendersong.dart end-to-end: parse a notation file → render every note
// through a voice → write audio. Runs the real CLI as a subprocess with the
// built-in voice (no SoundFont, so no network / glint needed), asserting a
// valid, non-trivial WAV and MP3 come out. The pitch-correctness of the render
// is covered by the render-→-detect acceptance in the repo's listen.dart flow.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'sf2_fixture.dart';

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

/// A format-0 MIDI holding one fat sustained chord ([keys] struck together for
/// a bar) — a dense many-voice sum, to prove the master doesn't crush it.
Uint8List _chordMidi(List<int> keys) {
  List<int> vlen(int v) {
    final s = [v & 0x7f];
    v >>= 7;
    while (v > 0) {
      s.insert(0, 0x80 | (v & 0x7f));
      v >>= 7;
    }
    return s;
  }

  final body = <int>[];
  for (final k in keys) {
    body.addAll([0x00, 0x90, k, 0x64]); // all note-ons at tick 0
  }
  body
    ..addAll(vlen(1920)) // after one 4/4 bar at tpq 480
    ..addAll([0x80, keys.first, 0]);
  for (final k in keys.skip(1)) {
    body.addAll([0x00, 0x80, k, 0]);
  }
  body.addAll([0x00, 0xFF, 0x2F, 0x00]);
  final len = body.length;
  return Uint8List.fromList([
    ...'MThd'.codeUnits, 0, 0, 0, 6, 0, 0, 0, 1, 1, 0xE0, //
    ...'MTrk'.codeUnits,
    (len >> 24) & 0xff, (len >> 16) & 0xff, (len >> 8) & 0xff, len & 0xff, //
    ...body,
  ]);
}

/// Peak and RMS of a PCM16 WAV (scans for the `data` chunk).
(double peak, double rms) _peakRms(Uint8List b) {
  final d = ByteData.sublistView(b);
  var off = 12, dataOff = -1, dataLen = 0;
  while (off + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(off, off + 4));
    final sz = d.getUint32(off + 4, Endian.little);
    if (id == 'data') {
      dataOff = off + 8;
      dataLen = sz;
    }
    off += 8 + sz + (sz & 1);
  }
  final n = dataLen ~/ 2;
  var peak = 0.0, sumSq = 0.0;
  for (var i = 0; i < n; i++) {
    final v = d.getInt16(dataOff + i * 2, Endian.little) / 32768.0;
    if (v.abs() > peak) peak = v.abs();
    sumSq += v * v;
  }
  return (peak, math.sqrt(sumSq / math.max(1, n)));
}

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
    'a dense many-voice chord is mastered clean, not crushed flat',
    () async {
      // The event-accurate MIDI path sums up to N voices with no gain staging;
      // the master must normalize + gently soft-clip, NOT slam a fixed-knee tanh
      // (which flattened a hot sum into a buzzy quasi-square — RMS≈peak).
      final sf2 = '${dir.path}/fix.sf2';
      File(sf2).writeAsBytesSync(
        oneSampleSf2(
          pcm: sineI16(2000, 8),
          sampleRate: 44100,
          rootKey: 60,
          loopStart: 0,
          loopEnd: 0,
        ),
      );
      final mid = '${dir.path}/chord.mid';
      File(mid).writeAsBytesSync(
        _chordMidi([48, 52, 55, 60, 64, 67, 72, 76]), // 8 simultaneous notes
      );
      final out = '${dir.path}/chord.wav';
      final r = await Process.run(
        'dart',
        ['run', 'bin/rendersong.dart', mid, out, '--sf2', sf2],
      );
      expect(r.exitCode, 0, reason: 'stderr: ${r.stderr}');
      final (peak, rms) = _peakRms(File(out).readAsBytesSync());
      expect(peak, greaterThan(0.5), reason: 'the chord actually rendered');
      expect(peak, lessThanOrEqualTo(0.95), reason: 'no hard clipping');
      // A clean chord keeps a healthy crest factor; a crushed one has RMS≈peak.
      expect(
        rms,
        lessThan(peak * 0.6),
        reason: 'RMS ${rms.toStringAsFixed(3)} vs peak '
            '${peak.toStringAsFixed(3)} — the mix is squashed',
      );
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
