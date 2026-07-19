// Structure round-trip matrix across the four module formats: two dimensions
// nothing else pinned —
//   * MULTI-INSTRUMENT mapping — a pattern whose cells reference several samples
//     keeps each cell pointing at the right instrument through
//     doc → convertTo<Fmt> → parseAnyModule (all four formats).
//   * CHANNEL COUNT — S3M/XM/IT carry a wide band (6 channels here); ProTracker
//     MOD is a 4-channel format, so a wider song is TRUNCATED to 4 on export
//     (channels 0–3 survive; the rest drop). Declared per-format (_wideFormats)
//     in the crisp_notation round-trip matrix's `droppedBy` spirit.
// Pure Dart.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Formats whose channel band is wider than MOD's fixed 4.
const _wideFormats = {ModuleFormat.s3m, ModuleFormat.xm, ModuleFormat.it};

DocSample _sample(double amp) {
  final pcm = Float64List(32);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = (i % 8 < 4) ? amp : -amp;
  }
  return DocSample(pcm: pcm, c5speed: 44100);
}

/// 1 channel, 3 rows each triggering a different instrument (1, 2, 3).
ModuleDoc _multiInst() => ModuleDoc(
      channelCount: 1,
      sourceFormat: ModuleFormat.it,
      order: [0],
      patterns: const [
        DocPattern(
          [
            [DocCell(note: 60, instrument: 1)],
            [DocCell(note: 62, instrument: 2)],
            [DocCell(note: 64, instrument: 3)],
          ],
          1,
        ),
      ],
      samples: [_sample(0.3), _sample(0.5), _sample(0.7)],
    );

/// 6 channels, each a distinct note on row 0 (one shared instrument).
ModuleDoc _sixDoc() => ModuleDoc(
      channelCount: 6,
      sourceFormat: ModuleFormat.it,
      order: [0],
      patterns: const [
        DocPattern(
          [
            [
              DocCell(note: 60, instrument: 1),
              DocCell(note: 62, instrument: 1),
              DocCell(note: 64, instrument: 1),
              DocCell(note: 65, instrument: 1),
              DocCell(note: 67, instrument: 1),
              DocCell(note: 69, instrument: 1),
            ],
          ],
          6,
        ),
      ],
      samples: [_sample(0.5)],
    );

void main() {
  group('structure round-trip matrix (doc → write → parse)', () {
    for (final fmt in ModuleFormat.values) {
      test('${fmt.name}: multi-instrument cells keep their mapping', () {
        final rows =
            parseAnyModule(convertDocTo(_multiInst(), fmt)).patterns.first.rows;
        expect(rows[0].first.instrument, 1);
        expect(rows[1].first.instrument, 2);
        expect(rows[2].first.instrument, 3);
        // The three referenced notes survive too.
        expect(
          [for (var r = 0; r < 3; r++) rows[r].first.note],
          [60, 62, 64],
        );
      });

      test('${fmt.name}: channel count per the format contract', () {
        final back = parseAnyModule(convertDocTo(_sixDoc(), fmt));
        if (_wideFormats.contains(fmt)) {
          expect(back.channelCount, 6, reason: '${fmt.name} keeps 6 channels');
        } else {
          expect(back.channelCount, 4, reason: 'MOD caps at 4 channels');
        }
        // Channels 0–3 always survive (the first four notes).
        final row0 = back.patterns.first.rows.first;
        expect(
          [for (var c = 0; c < 4; c++) row0[c].note],
          [60, 62, 64, 65],
        );
      });
    }

    test('MOD is the only format that truncates the channel band', () {
      final truncated = <String>[];
      for (final fmt in ModuleFormat.values) {
        if (parseAnyModule(convertDocTo(_sixDoc(), fmt)).channelCount < 6) {
          truncated.add(fmt.name);
        }
      }
      expect(truncated, ['mod']);
    });
  });
}
