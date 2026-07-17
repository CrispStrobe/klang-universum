// songFromModuleBytes — imports a real module (.mod/.s3m/.xm/.it) into a
// TrackerSong. Runs against the committed license-clean golden fixtures; asserts
// structure (channels/patterns/order) and that authored notes survive the
// row-major -> channel-major transpose. Pure Dart, no device audio.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart'
    show parseAnyModule;
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

void main() {
  for (final name in ['golden.mod', 'golden.s3m', 'golden.xm', 'golden.it']) {
    test('$name imports into a consistent TrackerSong', () {
      final bytes = _fixture(name);
      final doc = parseAnyModule(bytes);
      final song = songFromModuleBytes(bytes);

      // Structure matches the module.
      expect(song.channelCount, doc.channelCount < 1 ? 1 : doc.channelCount);
      expect(song.patterns.length, doc.patterns.length);
      expect(song.order, isNotEmpty);

      // Every pattern is channel-major and row-sized (the model invariant).
      for (final p in song.patterns) {
        expect(p.cells.length, song.channelCount);
        for (final col in p.cells) {
          expect(col.length, song.rows);
        }
      }

      // The module's first authored note survives the import somewhere.
      final firstNote = _firstDocNote(doc);
      if (firstNote != null) {
        final found = song.patterns.any(
          (p) => p.cells.any((col) => col.any((c) => c.midi == firstNote)),
        );
        expect(found, isTrue, reason: 'first module note $firstNote not found');
      }

      // Rendering the imported song produces audio (no crash, non-trivial).
      expect(song.renderCurrentPatternWav().length, greaterThan(44));
    });
  }
}

int? _firstDocNote(ModuleDoc doc) {
  for (final p in doc.patterns) {
    for (var r = 0; r < p.numRows; r++) {
      for (final cell in p.rows[r]) {
        if (cell.note >= 0) return cell.note;
      }
    }
  }
  return null;
}
