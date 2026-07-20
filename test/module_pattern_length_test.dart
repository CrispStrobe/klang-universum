// Pattern-length round-trip matrix. XM/IT patterns are variable-length; MOD and
// S3M are a FIXED 64 rows, so converting to them pads a short pattern and
// truncates a long one — a real playback change nothing else pinned:
//   * XM / IT keep the exact row count (16 / 32 / 128).
//   * MOD / S3M pad a short pattern to 64, but doc→mod/s3m now emits a pattern
//     break (Dxx / S3M `C`) on the last real row (a free empty cell) so a short
//     LOOP still plays at its authored length instead of running 48 silent rows.
//   * MOD / S3M truncate a pattern longer than 64 rows — content past row 63 is
//     dropped (an inherent format limit).
// Pure Dart.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixed64Formats = {ModuleFormat.mod, ModuleFormat.s3m};

DocSample _sample() {
  final pcm = Float64List(32);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = (i % 8 < 4) ? 0.5 : -0.5;
  }
  return DocSample(pcm: pcm);
}

/// A [rows]-row pattern: a note on row 0, empty elsewhere (so a short pattern's
/// LAST row is empty — the pattern-break lands there).
ModuleDoc _docRows(int rows) {
  final rl = <List<DocCell>>[
    for (var r = 0; r < rows; r++)
      [r == 0 ? const DocCell(note: 60, instrument: 1) : const DocCell()],
  ];
  return ModuleDoc(
    channelCount: 1,
    sourceFormat: ModuleFormat.mod,
    order: [0],
    patterns: [DocPattern(rl, 1)],
    samples: [_sample()],
  );
}

/// A [rows]-row pattern with a marker note (64) at [at].
ModuleDoc _docNoteAt(int rows, int at) {
  final rl = <List<DocCell>>[
    for (var r = 0; r < rows; r++)
      [
        if (r == 0)
          const DocCell(note: 60, instrument: 1)
        else if (r == at)
          const DocCell(note: 64, instrument: 1)
        else
          const DocCell(),
      ],
  ];
  return ModuleDoc(
    channelCount: 1,
    sourceFormat: ModuleFormat.mod,
    order: [0],
    patterns: [DocPattern(rl, 1)],
    samples: [_sample()],
  );
}

void main() {
  group('pattern-length round-trip matrix (doc → write → parse)', () {
    test('XM/IT preserve the exact row count', () {
      for (final rows in const [16, 32, 64, 128]) {
        for (final fmt in const [ModuleFormat.xm, ModuleFormat.it]) {
          final back = parseAnyModule(convertDocTo(_docRows(rows), fmt));
          expect(back.patterns.first.rows.length, rows, reason: fmt.name);
        }
      }
    });

    test('MOD/S3M are a fixed 64 rows', () {
      for (final rows in const [16, 32, 128]) {
        for (final fmt in _fixed64Formats) {
          final back = parseAnyModule(convertDocTo(_docRows(rows), fmt));
          expect(back.patterns.first.rows.length, 64, reason: fmt.name);
        }
      }
    });

    test('MOD/S3M break a padded short pattern at its authored length', () {
      // A 16-row loop with an empty last row → a Dxx/C break on row 15.
      for (final fmt in _fixed64Formats) {
        final back = parseAnyModule(convertDocTo(_docRows(16), fmt));
        expect(
          back.patterns.first.rows[15].first.effect,
          0xD, // Dxx pattern break (S3M `C` reads back as the doc's Dxx)
          reason: '${fmt.name} should break at row 15',
        );
        // No spurious break on a full-length pattern.
        final full = parseAnyModule(convertDocTo(_docRows(64), fmt));
        expect(full.patterns.first.rows[63].first.effect, 0);
      }
    });

    test('MOD/S3M truncate content past row 63', () {
      // A note at row 100 of a 128-row pattern is dropped on export.
      for (final fmt in _fixed64Formats) {
        final back = parseAnyModule(convertDocTo(_docNoteAt(128, 100), fmt));
        expect(back.patterns.first.rows.length, 64);
        final kept = back.patterns.first.rows.any((r) => r.first.note == 64);
        expect(kept, isFalse, reason: '${fmt.name} drops row 100');
      }
    });
  });
}
