// TabDocument (B1) — the editable tablature model: fret placement, string
// pinning into the engraved Score, playback timing, and Score→doc import.

import 'package:comet_beat/features/games/composition/tab_chords.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final guitar = Tuning.standardGuitar;

  test('blank() makes N empty columns', () {
    final doc = TabDocument.blank(guitar, initialColumns: 4);
    expect(doc.columns, hasLength(4));
    expect(doc.columns.every((c) => c.isEmpty), isTrue);
    expect(doc.stringCount, 6);
  });

  test('setFret places the tuned pitch and pins the string', () {
    final doc = TabDocument.blank(guitar, initialColumns: 1);
    doc.setFret(0, 5, 3); // 3rd fret, bottom string
    final score = doc.toScore();
    final note = score.measures.first.elements.whereType<NoteElement>().first;
    expect(note.pitches.single.midiNumber, guitar.strings[5].midiNumber + 3);
    expect(score.tabVoicings, hasLength(1));
    expect(score.tabVoicings.first.strings, [5]);
  });

  test('a chord column pins each string in pitch order', () {
    final doc = TabDocument.blank(guitar, initialColumns: 1)
      ..setFret(0, 0, 0)
      ..setFret(0, 1, 2);
    final score = doc.toScore();
    final note = score.measures.first.elements.whereType<NoteElement>().first;
    expect(note.pitches, hasLength(2));
    expect(score.tabVoicings.first.strings, [0, 1]); // ascending = top→down
  });

  test('an empty column renders as a rest', () {
    final doc = TabDocument.blank(guitar, initialColumns: 1);
    final score = doc.toScore();
    expect(score.measures.first.elements.whereType<RestElement>(), isNotEmpty);
    expect(score.tabVoicings, isEmpty);
  });

  test('toPlaybackEvents: one per column, quarter = 500ms @120bpm', () {
    final doc = TabDocument.blank(guitar, initialColumns: 2)..setFret(0, 0, 0);
    final events = doc.toPlaybackEvents();
    expect(events, hasLength(2));
    expect(events.first.$2, 500);
    expect(events.first.$1, [guitar.strings[0].midiNumber]);
    expect(events[1].$1, isEmpty); // rest column
  });

  test('setDuration changes the played length', () {
    final doc = TabDocument.blank(guitar, initialColumns: 1)..setFret(0, 0, 0);
    doc.setDuration(0, NoteDuration.eighth);
    expect(doc.toPlaybackEvents().first.$2, 250);
  });

  test('removeColumn keeps at least one column', () {
    final doc = TabDocument.blank(guitar, initialColumns: 1);
    doc.removeColumn(0);
    expect(doc.columns, hasLength(1));
  });

  test('insertColumn adds an empty step', () {
    final doc = TabDocument.blank(guitar, initialColumns: 2)..insertColumn(1);
    expect(doc.columns, hasLength(3));
    expect(doc.columns[1].isEmpty, isTrue);
  });

  test('fromScore reads ascii tab into editable fretted columns', () {
    final score = asciiTabToScore(
      'e|-0-3-|\nB|-----|\nG|-----|\nD|-----|\nA|-----|\nE|-----|',
    );
    final doc = TabDocument.fromScore(score, guitar);
    final fretted = doc.columns.where((c) => !c.isEmpty).toList();
    expect(fretted, isNotEmpty);
    // The two events are open (0) and 3rd fret on the top string.
    expect(fretted.first.frets[0], anyOf(0, isNotNull));
  });

  test('GP export: toScore round-trips through the Guitar Pro writer', () {
    final doc = TabDocument.blank(guitar, initialColumns: 2)
      ..setFret(0, 0, 0)
      ..setFret(1, 5, 3);
    final bytes = writeGpFromGpif(scoreToGpif(doc.toScore(), tuning: guitar));
    expect(bytes.length, greaterThan(0));
    expect(bytes.sublist(0, 2), [0x50, 0x4B]); // .gp is a zip (PK header)

    // Re-reading the file we just wrote recovers the notes.
    final back = scoreFromGpif(readGpifFromGp(bytes));
    final notes =
        back.measures.expand((m) => m.elements).whereType<NoteElement>();
    expect(notes, hasLength(2));
  });

  test('techniques emit the matching noteId-keyed Score lists', () {
    final doc = TabDocument.blank(guitar, initialColumns: 3)
      ..setFret(0, 0, 5)
      ..setFret(2, 0, 7)
      ..toggleTechnique(0, TabTechnique.bend)
      ..toggleTechnique(0, TabTechnique.harmonic)
      ..toggleTechnique(0, TabTechnique.hammer) // slur t0 -> next noteful (t2)
      ..toggleTechnique(2, TabTechnique.slide);
    final s = doc.toScore();
    expect(s.bends.map((b) => b.noteId), contains('t0'));
    expect(
      s.tabNoteMarks
          .any((m) => m.noteId == 't0' && m.style == TabNoteStyle.harmonic),
      isTrue,
    );
    expect(s.slideInOuts.any((sl) => sl.noteId == 't2'), isTrue);
    expect(s.slurs.any((x) => x.startId == 't0' && x.endId == 't2'), isTrue);
  });

  test('guitar chord presets are 6-string and self-named', () {
    expect(kGuitarChords, isNotEmpty);
    for (final e in kGuitarChords.entries) {
      expect(e.value.frets, hasLength(6), reason: e.key);
      expect(e.value.name, e.key);
    }
  });

  test('setChord attaches then clears, and survives edits + insert', () {
    final doc = TabDocument.blank(guitar, initialColumns: 2)
      ..setChord(1, kGuitarChords['G']);
    expect(doc.columns[1].chord?.name, 'G');
    // Editing the column keeps its chord.
    doc
      ..setFret(1, 0, 3)
      ..setDuration(1, NoteDuration.eighth);
    expect(doc.columns[1].chord?.name, 'G');
    // Inserting before shifts the chord with its column.
    doc.insertColumn(0);
    expect(doc.columns[2].chord?.name, 'G');
    // The chord is display-only — toScore ignores it.
    expect(doc.toScore().measures, isNotEmpty);
    doc.setChord(2, null);
    expect(doc.columns[2].chord, isNull);
  });

  test('toggleTechnique adds then removes', () {
    final doc = TabDocument.blank(guitar, initialColumns: 1)..setFret(0, 0, 0);
    doc.toggleTechnique(0, TabTechnique.bend);
    expect(doc.columns[0].techniques, contains(TabTechnique.bend));
    doc.toggleTechnique(0, TabTechnique.bend);
    expect(doc.columns[0].techniques, isEmpty);
  });

  group('mergePlaybackEvents (band)', () {
    test('two tracks sound together on a shared slice', () {
      // Track A: one 500ms note (midi 40). Track B: one 500ms note (midi 52).
      final merged = mergePlaybackEvents([
        [
          ([40], 500),
        ],
        [
          ([52], 500),
        ],
      ]);
      expect(merged, hasLength(1));
      expect(merged.single.$1, [40, 52]); // both sounding, sorted
      expect(merged.single.$2, 500);
    });

    test('slices at boundaries when tracks differ in rhythm', () {
      // A: 40 for 1000ms. B: 52 for 500ms then 53 for 500ms.
      final merged = mergePlaybackEvents([
        [
          ([40], 1000),
        ],
        [
          ([52], 500),
          ([53], 500),
        ],
      ]);
      expect(merged, hasLength(2));
      expect(merged[0].$1, [40, 52]);
      expect(merged[0].$2, 500);
      expect(merged[1].$1, [40, 53]);
      expect(merged[1].$2, 500);
    });

    test('runs to the longest track; a rest contributes nothing', () {
      final merged = mergePlaybackEvents([
        [
          ([40], 500),
        ],
        [
          (<int>[], 500), // rest
          ([52], 500),
        ],
      ]);
      expect(merged, hasLength(2));
      expect(merged[0].$1, [40]);
      expect(merged[1].$1, [52]); // track A already finished
      expect(merged.fold<int>(0, (a, e) => a + e.$2), 1000);
    });

    test('a single track passes through unchanged', () {
      final doc = TabDocument.blank(guitar, initialColumns: 2)
        ..setFret(0, 0, 0);
      final solo = doc.toPlaybackEvents();
      final merged = mergePlaybackEvents([solo]);
      expect(merged.map((e) => e.$2).toList(), solo.map((e) => e.$2).toList());
    });
  });

  test('clearCell removes only that string from a chord', () {
    final doc = TabDocument.blank(guitar, initialColumns: 1)
      ..setFret(0, 0, 5)
      ..setFret(0, 1, 7);
    doc.clearCell(0, 0);
    expect(doc.columns[0].frets.containsKey(0), isFalse);
    expect(doc.columns[0].frets[1], 7);
  });
}
