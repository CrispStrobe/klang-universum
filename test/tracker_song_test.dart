// TrackerSong — the Advanced Tracker's document model. Covers the arrangement
// layer the Beginner grid lacks: endless pattern length (setRows), endless
// tracks (add/removeChannel), and multi-pattern songs (patterns + order list).
// Pure Dart, no device audio — mirrors tracker_engine_test.dart.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

int _wavPcmLen(Uint8List wav) => (wav.length - 44) ~/ 2; // samples after header

void main() {
  group('TrackerSong defaults', () {
    test('starts with one pattern, one order entry, the default band', () {
      final song = TrackerSong();
      expect(song.patterns.length, 1);
      expect(song.order, [0]);
      expect(song.channelCount, defaultTrackerChannels().length);
      expect(song.rows, 32);
      expect(song.isEmpty, isTrue);
      // Every pattern column is channel-major and row-sized.
      expect(song.current.cells.length, song.channelCount);
      for (final col in song.current.cells) {
        expect(col.length, song.rows);
      }
    });
  });

  group('endless length (setRows)', () {
    test('grows and shrinks every pattern, keeping notes in range', () {
      final song = TrackerSong()..addPattern();
      // Place a note near the end of a 32-row pattern on channel 0.
      song.engine.setCell(0, 30, const TrackerCell(midi: 60));
      song.setRows(64);
      expect(song.rows, 64);
      for (final p in song.patterns) {
        for (final col in p.cells) {
          expect(col.length, 64);
        }
      }
      // The note at row 30 survived the grow.
      expect(song.engine.cellAt(0, 30).midi, 60);

      // Shrinking below the note drops it; rows that remain are intact.
      song.engine.setCell(0, 10, const TrackerCell(midi: 62));
      song.setRows(16);
      expect(song.rows, 16);
      expect(song.engine.cellAt(0, 10).midi, 62);
      expect(song.current.cells.first.length, 16);
    });

    test('a 128-row pattern is far past the Beginner one-bar ceiling', () {
      final song = TrackerSong()..setRows(128);
      expect(song.rows, 128);
      // Render still produces a valid, longer loop.
      final wav = song.renderCurrentPatternWav();
      expect(wav.length, greaterThan(44));
    });
  });

  group('endless tracks (add/removeChannel)', () {
    test('addChannel grows the band and every pattern column', () {
      final song = TrackerSong()..addPattern();
      final before = song.channelCount;
      song.addChannel();
      expect(song.channelCount, before + 1);
      for (final p in song.patterns) {
        expect(p.cells.length, before + 1);
        expect(p.cells.last.length, song.rows);
      }
      // The new channel is editable and renders.
      song.engine
          .setCell(song.channelCount - 1, 0, const TrackerCell(midi: 64));
      expect(song.engine.cellAt(song.channelCount - 1, 0).midi, 64);
    });

    test('removeChannel keeps existing notes on the surviving channels', () {
      final song = TrackerSong();
      song.engine.setCell(0, 0, const TrackerCell(midi: 60)); // ch0
      song.engine.setCell(2, 1, const TrackerCell(midi: 67)); // ch2
      song.removeChannel(1); // drop the middle channel
      expect(song.channelCount, defaultTrackerChannels().length - 1);
      expect(song.engine.cellAt(0, 0).midi, 60); // ch0 intact
      expect(song.engine.cellAt(1, 1).midi, 67); // old ch2 shifted to ch1
    });

    test('cannot remove the last channel', () {
      final song = TrackerSong(
        channels: [
          TrackerChannel(
            id: 'only',
            instrument: const AdditiveInstrument('piano', Instrument.piano),
            rows: 32,
          ),
        ],
      );
      song.removeChannel(0);
      expect(song.channelCount, 1);
    });
  });

  group('multi-pattern songs + order list', () {
    test('selectPattern saves and restores per-pattern cells', () {
      final song = TrackerSong();
      song.engine.setCell(0, 0, const TrackerCell(midi: 60)); // pattern 0
      final p1 = song.addPattern();
      song.selectPattern(p1);
      expect(song.engine.cellAt(0, 0).isEmpty, isTrue); // fresh pattern
      song.engine.setCell(0, 0, const TrackerCell(midi: 72)); // pattern 1
      song.selectPattern(0);
      expect(song.engine.cellAt(0, 0).midi, 60); // pattern 0 restored
      song.selectPattern(p1);
      expect(song.engine.cellAt(0, 0).midi, 72); // pattern 1 restored
    });

    test('addPattern(cloneCurrent) copies without aliasing', () {
      final song = TrackerSong();
      song.engine.setCell(0, 0, const TrackerCell(midi: 60));
      final clone = song.addPattern(cloneCurrent: true);
      song.selectPattern(clone);
      expect(song.engine.cellAt(0, 0).midi, 60); // copied
      song.engine.setCell(0, 0, const TrackerCell(midi: 65)); // edit the clone
      song.selectPattern(0);
      expect(song.engine.cellAt(0, 0).midi, 60); // original untouched
    });

    test('song length is the sum of its order entries', () {
      final song = TrackerSong(); // 32 rows
      song.engine.setCell(0, 0, const TrackerCell(midi: 60));
      final p1 = song.addPattern(cloneCurrent: true);
      // Order: pattern0, pattern1, pattern0  -> three patterns back to back.
      song.addToOrder(p1);
      song.addToOrder(0);
      expect(song.order, [0, p1, 0]);

      final one = song.renderCurrentPatternWav();
      final full = song.renderSongWav();
      final onePcm = _wavPcmLen(one);
      final fullPcm = _wavPcmLen(full);
      // Three patterns -> ~3x one pattern (allow rounding slack).
      expect((fullPcm - 3 * onePcm).abs(), lessThan(8));
      expect(song.patternStartMs(1), song.timing.totalMs);
      expect(song.songTotalMs, song.timing.totalMs * 3);
    });

    test('removePattern remaps the order list and keeps a valid current', () {
      final song = TrackerSong();
      final p1 = song.addPattern(); // index 1
      final p2 = song.addPattern(); // index 2
      song.addToOrder(p1);
      song.addToOrder(p2);
      expect(song.order, [0, 1, 2]);
      song.removePattern(1); // drop the middle pattern
      expect(song.patterns.length, 2);
      // Entries that referenced pattern 1 are gone; pattern 2 shifts to 1.
      expect(song.order, [0, 1]);
      expect(song.currentIndex, inInclusiveRange(0, 1));
    });

    test('cannot remove the last pattern or empty the order', () {
      final song = TrackerSong();
      song.removePattern(0);
      expect(song.patterns.length, 1);
      song.removeFromOrder(0);
      expect(song.order, isNotEmpty);
    });
  });

  group('orderIndexAtMs', () {
    test('maps song time to the sounding order position', () {
      final song = TrackerSong(); // 32 rows
      song.addToOrder(0);
      song.addToOrder(0); // order = [0,0,0]
      final patMs = song.timing.totalMs;
      expect(song.orderIndexAtMs(0), 0);
      expect(song.orderIndexAtMs(patMs + 1), 1);
      expect(song.orderIndexAtMs(2 * patMs + 1), 2);
      // Past the end clamps to the last entry.
      expect(song.orderIndexAtMs(99 * patMs), 2);
    });
  });
}
