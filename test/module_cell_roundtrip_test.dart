// Cell-content round-trip matrix across the four module formats. Pins what a
// pattern cell carries — note, instrument, and the volume column — through
// `doc → convertTo<Fmt> → parseAnyModule` for MOD / S3M / XM / IT.
//
// The N×N convert matrix (module_convert_test) proves a note + sample survive a
// conversion; this locks the per-cell fidelity contract, in particular the one
// real fidelity DROP: the classic ProTracker `.mod` format has NO volume column
// (per-note volume lives only in a Cxx effect), so a cell's volume column is
// lost on export to MOD while S3M / XM / IT keep it exactly.
//
// Volume-column support is declared per-format (`_volFormats`) in the
// crisp_notation round-trip matrix's `droppedBy` style: a supported cell is a
// regression lock, the MOD drop is an explicit expectation that fails loudly if
// it ever changes (e.g. if the MOD writer starts emitting Cxx to carry volume).
// Effect-column preservation is deliberately out of scope: effect semantics are
// format-specific and translated on conversion, not a simple field round-trip.
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

        test('the volume column survives per the format contract', () {
          final c = _cellAfter(
            docWithCell(const DocCell(note: 60, instrument: 1, volume: 32)),
            fmt,
          );
          // Note + instrument always survive…
          expect(c.note, 60);
          expect(c.instrument, 1);
          // …the volume column only where the format carries one.
          if (_volFormats.contains(fmt)) {
            expect(c.volume, 32, reason: '${fmt.name} must keep the volume');
          } else {
            expect(c.volume, -1, reason: 'MOD has no volume column');
          }
        });
      });
    }

    test('MOD is the only format that drops the volume column', () {
      final doc = docWithCell(
        const DocCell(note: 60, instrument: 1, volume: 40),
      );
      final dropped = <String>[];
      for (final fmt in ModuleFormat.values) {
        if (_cellAfter(doc, fmt).volume != 40) dropped.add(fmt.name);
      }
      expect(dropped, ['mod']);
    });
  });
}
