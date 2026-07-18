// The bundled CC0 sample library: the decode path (WAV bytes → SampleInstrument)
// and that each committed VCSL percussion one-shot loads + plays. Reads the
// asset files straight from disk (no rootBundle) so it runs headless.

import 'dart:io';

import 'package:comet_beat/core/audio/sound_library.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bundled CC0 percussion', () {
    test('every catalog entry is a committed WAV under assets/', () {
      expect(kBundledPercussion, isNotEmpty);
      for (final info in kBundledPercussion) {
        final f = File(info.assetPath);
        expect(f.existsSync(), isTrue, reason: 'missing ${info.assetPath}');
        expect(info.category, SoundCategory.drum);
      }
    });

    test('a bundled sample decodes into an audible SampleInstrument', () {
      const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
      for (final info in kBundledPercussion) {
        final bytes = File(info.assetPath).readAsBytesSync();
        final inst = bundledSampleInstrument(info, bytes);
        expect(inst, isA<SampleInstrument>());
        expect(inst.id, info.id);
        expect(inst.sample.length, greaterThan(0));
        expect(soundCategoryOf(inst), SoundCategory.recorded);

        // Placing a note renders audio; an empty channel is silence.
        final cells = [
          const TrackerCell(midi: 60),
          ...List<TrackerCell>.filled(timing.rows - 1, TrackerCell.empty),
        ];
        final buf = inst.renderChannel(cells, timing);
        expect(buf.length, timing.totalSamples);
        expect(buf.any((v) => v != 0), isTrue, reason: '${info.id} silent');
      }
    });

    test('the LICENSE.txt (CC0 provenance) ships with the samples', () {
      final license = File('assets/sounds/percussion/LICENSE.txt');
      expect(license.existsSync(), isTrue);
      final text = license.readAsStringSync();
      expect(text, contains('CC0'));
      expect(text, contains('VCSL'));
    });
  });
}
