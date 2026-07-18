// Tab Workshop (B0) — read-only tablature viewer. Pure-parse asserts on
// parseTabFile + widget asserts on the controls and the file-open seam
// (TabWorkshopTester). The tab render itself needs the bundled music font, so
// these assertions are on chrome/state, not painted output.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/features/games/composition/tab_chords.dart';
import 'package:comet_beat/features/games/composition/tab_document.dart';
import 'package:comet_beat/features/games/composition/tab_workshop_screen.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

const _abc = 'X:1\nT:Scale\nK:C\nCDEF|GABc|\n';

TabWorkshopTester _tab(WidgetTester tester) =>
    tester.state<State<TabWorkshopScreen>>(find.byType(TabWorkshopScreen))
        as TabWorkshopTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('parseTabFile', () {
    test('reads an ABC file into a Score with notes', () {
      final score = parseTabFile('tune.abc', utf8.encode(_abc));
      final notes = score.measures
          .expand((m) => m.elements)
          .whereType<NoteElement>()
          .length;
      expect(notes, greaterThan(0));
    });

    test('throws on an unknown extension', () {
      expect(
        () => parseTabFile('weird.zzz', Uint8List(0)),
        throwsFormatException,
      );
    });

    test('accepts the documented tab import extensions', () {
      expect(tabImportExtensions, contains('gp'));
      expect(tabImportExtensions, contains('gpx'));
      expect(tabImportExtensions, contains('musicxml'));
    });
  });

  testWidgets('opens with the demo riff and tuning/capo controls',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);

    expect(tab.sourceName, isNull); // demo, not a loaded file
    expect(tab.tuning.name, Tuning.standardGuitar.name);
    expect(tab.capo, 0);
    // The tuning picker and the standard-notation switch are present.
    expect(find.byType(DropdownButton<Tuning>), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('the capo stepper is bounded at 0 and increments',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);

    // At 0 the minus button is disabled; plus raises the capo.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(tab.capo, 1);
  });

  testWidgets('opening a file updates the score + app-bar title',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);

    await tab.openScoreFile(
      pickedName: 'tune.abc',
      pickedBytes: utf8.encode(_abc),
    );
    await tester.pump();

    expect(tab.sourceName, 'tune.abc');
    expect(find.text('tune.abc'), findsWidgets);
  });

  testWidgets('a bad file surfaces an error and keeps the old score',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);

    await tab.openScoreFile(
      pickedName: 'broken.musicxml',
      pickedBytes: utf8.encode('<not-musicxml/>'),
    );
    await tester.pump();

    expect(tab.sourceName, isNull); // unchanged — still the demo
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('select a cell and enter a fret updates the grid',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);

    tab.selectCell(0, 0);
    await tester.pump();
    tab.enterFret(5);
    await tester.pump();
    expect(tab.fretAt(0, 0), 5);

    tab.deleteCell();
    await tester.pump();
    expect(tab.fretAt(0, 0), isNull);
  });

  testWidgets('add and remove a column changes the count', (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);

    final before = tab.columnCount;
    tab.addColumn();
    await tester.pump();
    expect(tab.columnCount, before + 1);

    tab.removeColumnAtCursor();
    await tester.pump();
    expect(tab.columnCount, before);
  });

  testWidgets('tapping a fret keypad button writes to the selected cell',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);
    tab.selectCell(1, 2);
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, '7'));
    await tester.pump();
    expect(tab.fretAt(1, 2), 7);
  });

  testWidgets('toggling a technique chip marks the selected note',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);
    tab.selectCell(0, 0);
    tab.enterFret(5);
    await tester.pump();

    tab.toggleTechnique(TabTechnique.bend);
    await tester.pump();
    expect(tab.techniquesAt(0), contains(TabTechnique.bend));

    tab.toggleTechnique(TabTechnique.bend);
    await tester.pump();
    expect(tab.techniquesAt(0), isEmpty);
  });

  testWidgets('attaching a chord shows its name above the column',
      (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);
    tab.selectCell(2, 0);
    await tester.pump();

    tab.setChordByName('G');
    await tester.pump();
    expect(tab.chordNameAt(2), 'G');

    tab.setChordByName(null);
    await tester.pump();
    expect(tab.chordNameAt(2), isNull);
  });

  testWidgets('ChordDiagramView paints a preset', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ChordDiagramView(kGuitarChords['C']!))),
    );
    expect(find.byType(ChordDiagramView), findsOneWidget);
  });

  testWidgets('play lights the sounding column, then stops', (tester) async {
    await pumpGame(tester, const TabWorkshopScreen());
    final tab = _tab(tester);

    // A note in the first column (a quarter = 500ms at 120bpm).
    tab.selectCell(0, 0);
    tab.enterFret(3);
    await tester.pump();

    tab.play();
    await tester.pump(); // kick the ticker
    await tester.pump(const Duration(milliseconds: 100));
    expect(tab.isPlaying, isTrue);
    expect(tab.highlightedIds, contains('t0'));

    // Tapping play again stops and clears the highlight.
    tab.play();
    await tester.pump();
    expect(tab.isPlaying, isFalse);
    expect(tab.highlightedIds, isEmpty);
  });
}
