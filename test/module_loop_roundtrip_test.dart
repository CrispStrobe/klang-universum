// Sample-loop round-trip matrix across all four module formats. Pins the loop
// metadata (loopStart / loopLength / bidirectional flag) through
// `doc → convertTo<Fmt> → parseAnyModule` for MOD / S3M / XM / IT.
//
// The existing pingpong_loop_test proves the IT/XM writers EMIT the bidi flag;
// this locks the FULL cross-format contract, including the two things nothing
// else asserted:
//   * loop POINTS (start + length in samples) survive every format, and
//   * MOD / S3M — which have no bidirectional loop — correctly DROP a ping-pong
//     loop to a plain forward loop (flag off) while KEEPING the loop itself.
//
// Ping-pong support is declared per-format (bidiFormats) like the crisp_notation
// round-trip matrix's `droppedBy`: a supported cell is a regression lock, a
// dropped cell is an explicit expectation that fails loudly if it ever changes.
// Pure Dart — no device audio.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:flutter_test/flutter_test.dart';

const _emptyRow = <DocCell>[DocCell.empty];

/// The formats whose sample loop can be bidirectional ("ping-pong"). MOD and
/// S3M only carry a forward loop, so a ping-pong source must degrade to forward.
const _bidiFormats = {ModuleFormat.xm, ModuleFormat.it};

/// A minimal 1-channel module carrying one looping sample. Loop points are
/// word-aligned (8 / 32) so MOD's word-granular loop storage is exact.
ModuleDoc docWithLoop({required bool pingPong}) {
  final pcm = Float64List(64);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = (i % 16 < 8) ? 0.5 : -0.5;
  }
  return ModuleDoc(
    channelCount: 1,
    sourceFormat: ModuleFormat.it,
    order: [0],
    patterns: const [
      DocPattern([_emptyRow], 1),
    ],
    samples: [
      DocSample(
        pcm: pcm,
        c5speed: 44100,
        loopStart: 8,
        loopLength: 32,
        pingPong: pingPong,
      ),
    ],
  );
}

void main() {
  group('sample-loop round-trip matrix (doc → write → parse)', () {
    for (final fmt in ModuleFormat.values) {
      group(fmt.name, () {
        test('a forward loop survives with its points intact', () {
          final back =
              parseAnyModule(convertDocTo(docWithLoop(pingPong: false), fmt));
          final s = back.usedSamples.first;
          expect(s.loopStart, 8, reason: 'loopStart lost in ${fmt.name}');
          expect(s.loopLength, 32, reason: 'loopLength lost in ${fmt.name}');
          expect(s.pingPong, isFalse); // forward stays forward
          expect(s.pcm.length, 64); // the sample body is unchanged
        });

        test('a ping-pong loop round-trips per the format contract', () {
          final back =
              parseAnyModule(convertDocTo(docWithLoop(pingPong: true), fmt));
          final s = back.usedSamples.first;
          // The loop itself survives in EVERY format…
          expect(s.loopStart, 8);
          expect(s.loopLength, 32);
          // …but the bidirectional FLAG only survives where the format carries
          // it; MOD/S3M degrade it to a plain forward loop.
          expect(
            s.pingPong,
            _bidiFormats.contains(fmt),
            reason: 'ping-pong contract wrong for ${fmt.name}',
          );
        });
      });
    }

    test('MOD/S3M degrade ping-pong to forward but never drop the loop', () {
      for (final fmt in const [ModuleFormat.mod, ModuleFormat.s3m]) {
        final s = parseAnyModule(convertDocTo(docWithLoop(pingPong: true), fmt))
            .usedSamples
            .first;
        expect(s.pingPong, isFalse, reason: '${fmt.name} has no bidi loop');
        expect(
          s.loopLength,
          greaterThan(0),
          reason: '${fmt.name} must keep the forward loop',
        );
      }
    });
  });
}
