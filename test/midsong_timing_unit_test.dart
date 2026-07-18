// Unit tests for Feature A — mid-song tempo/speed changes (own tests, alongside
// the orchestrator's midsong_timing_acceptance_test.dart). These pin the subtle
// bits: the variable-timing GATE (single vs. mid-song value), walkFlow's per-row
// annotation, the summed-duration length + map consistency, and that a
// NON-ADDITIVE (sfxr/sample) note triggered after a tempo change still lands at
// the correct accumulated sample offset.

import 'dart:math';

import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replayer.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

TrackerCell fxx(int param) => TrackerCell(fxCmd: kFxSetSpeed, fxParam: param);

void main() {
  group('variable-timing gate (songUsesVariableTiming)', () {
    test('no Fxx at all → not variable (uniform path)', () {
      final s = TrackerSong(timing: const TrackerTiming(rows: 8));
      s.engine.setCell(0, 0, const TrackerCell(midi: 60));
      s.syncCurrent();
      expect(songUsesVariableTiming(s), isFalse);
    });

    test('a single Fxx tempo (set at row 0, whole song) → not variable', () {
      final s = TrackerSong(timing: const TrackerTiming(rows: 8));
      s.engine.setCell(0, 0, const TrackerCell(midi: 60));
      s.engine.setCell(1, 0, fxx(0x50)); // 0x50 = 80 BPM, from the very start
      s.syncCurrent();
      expect(songUsesVariableTiming(s), isFalse);
    });

    test('two order entries at different tempos → variable', () {
      final s = TrackerSong(
        timing: const TrackerTiming(rows: 8),
        patternCount: 2,
      );
      s.selectPattern(1);
      s.engine.setCell(0, 0, fxx(0x3C)); // 60 BPM at entry 1
      s.order
        ..clear()
        ..addAll([0, 1]);
      s.syncCurrent();
      expect(songUsesVariableTiming(s), isTrue);
    });

    test(
        'a tempo that first appears at entry 1 (entry 0 at song default) '
        '→ variable even though only one Fxx exists', () {
      final s = TrackerSong(
        timing: const TrackerTiming(rows: 8),
        patternCount: 2,
      );
      s.selectPattern(1);
      s.engine.setCell(0, 0, fxx(0x50)); // 80 BPM only in entry 1
      s.order
        ..clear()
        ..addAll([0, 1]);
      s.syncCurrent();
      expect(songUsesVariableTiming(s), isTrue);
    });

    test('two distinct SPEEDS (tempo constant) → variable', () {
      final s = TrackerSong(
        timing: const TrackerTiming(rows: 8),
        patternCount: 2,
      );
      s.selectPattern(0);
      s.engine.setCell(0, 0, fxx(0x06));
      s.selectPattern(1);
      s.engine.setCell(0, 0, fxx(0x02));
      s.order
        ..clear()
        ..addAll([0, 1]);
      s.syncCurrent();
      expect(songUsesVariableTiming(s), isTrue);
    });
  });

  group('walkFlow per-row annotation', () {
    test('rows default to the song tempo and kDefaultTicksPerRow until set',
        () {
      final s = TrackerSong(
        timing: const TrackerTiming(rows: 4, tempoBpm: 100),
        patternCount: 2,
      );
      s.selectPattern(1);
      s.engine.setCell(0, 2, fxx(0x08)); // speed 8 mid-entry-1
      s.order
        ..clear()
        ..addAll([0, 1]);
      s.syncCurrent();

      final played = walkFlow(s);
      // Entry 0: song defaults throughout.
      for (final p in played.where((p) => p.orderIndex == 0)) {
        expect(p.tempoBpm, 100);
        expect(p.ticksPerRow, 6); // kDefaultTicksPerRow
      }
      // Entry 1: speed 8 takes effect ON row 2 and persists.
      final e1 = played.where((p) => p.orderIndex == 1).toList();
      expect(e1[0].ticksPerRow, 6);
      expect(e1[1].ticksPerRow, 6);
      expect(e1[2].ticksPerRow, 8);
      expect(e1[3].ticksPerRow, 8);
    });
  });

  group('length + map consistency', () {
    test('variableSongTotalMs sums the per-row durations', () {
      final s = TrackerSong(
        timing: const TrackerTiming(rows: 8),
        patternCount: 2,
      );
      s.selectPattern(1);
      s.engine.setCell(0, 0, fxx(0x3C)); // 60 BPM in entry 1
      s.order
        ..clear()
        ..addAll([0, 1]);
      s.syncCurrent();
      // 8 rows @ 125 ms + 8 rows @ 250 ms.
      expect(variableSongTotalMs(s), 8 * 125 + 8 * 250);
      expect(s.songTotalMs, variableSongTotalMs(s));
    });

    test('resolveTimingMap agrees with replaySong().timing (variable path)',
        () {
      final s = TrackerSong(
        timing: const TrackerTiming(rows: 8),
        patternCount: 2,
      );
      s.selectPattern(0);
      s.engine.setCell(0, 0, const TrackerCell(midi: 60));
      s.selectPattern(1);
      s.engine.setCell(1, 0, fxx(0x3C));
      s.engine.setCell(0, 0, const TrackerCell(midi: 62));
      s.order
        ..clear()
        ..addAll([0, 1]);
      s.syncCurrent();

      expect(
        resolveTimingMap(s).map((r) => r.toString()).toList(),
        replaySong(s).timing.map((r) => r.toString()).toList(),
      );
    });
  });

  group('non-additive placement after a tempo change', () {
    test(
        'an sfxr note triggered in the slowed second half lands at the '
        'accumulated offset (silent before, audible at/after)', () {
      // Default band channel 2 ("zap") is a non-additive sfxr voice. Entry 0 is
      // empty (8 rows @ 120 BPM), entry 1 drops to 60 BPM and triggers the note
      // on its first row → the only sound starts at sample 8*round(125ms).
      final s = TrackerSong(
        timing: const TrackerTiming(rows: 8),
        patternCount: 2,
      );
      s.selectPattern(1);
      s.engine.setCell(0, 0, fxx(0x3C)); // tempo → 60 on ch0 (silent, no note)
      s.engine.setCell(2, 0, const TrackerCell(midi: 60)); // zap note
      s.order
        ..clear()
        ..addAll([0, 1]);
      s.syncCurrent();

      expect(songUsesVariableTiming(s), isTrue);
      final pcm = replaySong(s).pcm;

      final onset = 8 * (125 * kSampleRate / 1000).round(); // 8 * 5513 = 44104
      // Silent well before the onset.
      var before = 0;
      for (var i = 0; i < onset - 500; i++) {
        before = max(before, pcm[i].abs());
      }
      expect(before, 0, reason: 'nothing should sound before the slow half');
      // Audible somewhere in the note's run after the onset.
      var after = 0;
      for (var i = onset; i < pcm.length; i++) {
        after = max(after, pcm[i].abs());
      }
      expect(after, greaterThan(200), reason: 'the note sounds after the drop');
    });
  });
}
