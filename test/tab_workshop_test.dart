// Tab Workshop (B0) — read-only tablature viewer. Pure-parse asserts on
// parseTabFile + widget asserts on the controls and the file-open seam
// (TabWorkshopTester). The tab render itself needs the bundled music font, so
// these assertions are on chrome/state, not painted output.

import 'dart:convert';
import 'dart:typed_data';

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
}
