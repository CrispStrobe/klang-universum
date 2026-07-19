// Cell-content round-trip matrix across the four module formats. Pins what a
// pattern cell carries — note, instrument, and the volume column — through
// `doc → convertTo<Fmt> → parseAnyModule` for MOD / S3M / XM / IT.
//
// The N×N convert matrix (module_convert_test) proves a note + sample survive a
// conversion; this locks the per-cell fidelity contract for a note's VOLUME,
// which each format represents differently: S3M / XM / IT carry it in a dedicated
// volume column, while classic ProTracker `.mod` has no volume column and instead
// carries it as a Cxx set-volume effect. Either way the volume is preserved — the
// matrix asserts the format-appropriate representation and that NO format drops
// it outright.
//
// Which formats use the volume column is declared per-format (`_volFormats`) in
// the crisp_notation round-trip matrix's `droppedBy` style: a supported cell is a
// regression lock; the MOD-via-Cxx path is an explicit expectation that fails
// loudly if it changes. Effect-column preservation of *other* effects is out of
// scope: effect semantics are format-specific and translated on conversion.
// Pure Dart — no device audio.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Formats that carry a per-note volume column. MOD has none (volume only via a
/// Cxx effect), so a cell's volume column is dropped on export to `.mod`.
const _volFormats = {ModuleFormat.s3m, ModuleFormat.xm, ModuleFormat.it};

/// A 1-channel, 1-row module whose single cell is [cell], backed by one sample.
ModuleDoc docWithCell(DocCell cell) {
  final pcm = Float64List(32);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = (i % 8 < 4) ? 0.5 : -0.5;
  }
  return ModuleDoc(
    channelCount: 1,
    sourceFormat: ModuleFormat.it,
    order: [0],
    patterns: [
      DocPattern(
        [
          [cell],
        ],
        1,
      ),
    ],
    samples: [DocSample(pcm: pcm, c5speed: 44100)],
  );
}

DocCell _cellAfter(ModuleDoc doc, ModuleFormat fmt) =>
    parseAnyModule(convertDocTo(doc, fmt)).patterns.first.rows.first.first;

void main() {
  group('cell-content round-trip matrix (doc → write → parse)', () {
    for (final fmt in ModuleFormat.values) {
      group(fmt.name, () {
        test('note + instrument survive', () {
          final c = _cellAfter(
            docWithCell(const DocCell(note: 72, instrument: 1)),
            fmt,
          );
          expect(c.note, 72, reason: 'note lost in ${fmt.name}');
          expect(c.instrument, 1, reason: 'instrument lost in ${fmt.name}');
        });

        test('a note volume survives per the format contract', () {
          final c = _cellAfter(
            docWithCell(const DocCell(note: 60, instrument: 1, volume: 32)),
            fmt,
          );
          // Note + instrument always survive…
          expect(c.note, 60);
          expect(c.instrument, 1);
          if (_volFormats.contains(fmt)) {
            // …S3M/XM/IT carry it in the dedicated volume column.
            expect(c.volume, 32, reason: '${fmt.name} must keep the volume');
          } else {
            // …MOD has no volume column, so it carries the volume as a Cxx
            // set-volume effect instead of dropping it.
            expect(c.volume, -1, reason: 'MOD has no volume column');
            expect(c.effect, 0xC, reason: 'MOD should carry volume as Cxx');
            expect(c.effectParam, 32);
          }
        });
      });
    }

    test('every format preserves a note volume (column or Cxx), none drops it',
        () {
      final doc = docWithCell(
        const DocCell(note: 60, instrument: 1, volume: 40),
      );
      for (final fmt in ModuleFormat.values) {
        final c = _cellAfter(doc, fmt);
        // The volume is recoverable either from the volume column…
        final fromColumn = c.volume == 40;
        // …or from a Cxx set-volume effect (MOD's representation).
        final fromCxx = c.effect == 0xC && c.effectParam == 40;
        expect(
          fromColumn || fromCxx,
          isTrue,
          reason: '${fmt.name} lost the note volume',
        );
      }
    });
  });
}
