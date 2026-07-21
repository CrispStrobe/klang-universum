// Which Seventh? — the seventh-quality ear game. No staff is shown; a plain
// provider harness is enough. We tap the button matching the game's own report
// of the correct quality.

import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/chords/seventh_ear_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

SeventhEarTester _game(WidgetTester tester) =>
    tester.state<State<SeventhEarScreen>>(find.byType(SeventhEarScreen))
        as SeventhEarTester;

const _labels = {
  SeventhKind.major7: 'Major 7',
  SeventhKind.dominant7: 'Dominant 7',
  SeventhKind.minor7: 'Minor 7',
  SeventhKind.halfDim7: 'Half-diminished',
};

Future<void> _answerCorrectly(WidgetTester tester) async {
  await tester.tap(find.text(_labels[_game(tester).answer]!));
  await tester.pump(const Duration(milliseconds: 800)); // auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('offers the three base qualities and records under chords.hear',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const SeventhEarScreen(), sri: sri);

    expect(find.text('Major 7'), findsOneWidget);
    expect(find.text('Dominant 7'), findsOneWidget);
    expect(find.text('Minor 7'), findsOneWidget);
    // Half-diminished is a 2★ addition — not offered at the base tier.
    expect(find.text('Half-diminished'), findsNothing);

    await _answerCorrectly(tester);
    expect(sri.getDetailedBreakdown()['chords']!.keys, ['hear']);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const SeventhEarScreen(), sri: sri);

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answerCorrectly(tester);
    }
    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });

  testWidgets('at 2 stars the half-diminished quality is added',
      (tester) async {
    final progress = ProgressService();
    await progress.load();
    progress.recordResult('seventh_ear', score: 700, stars: 2);

    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(
      tester,
      const SeventhEarScreen(),
      sri: sri,
      extraProviders: [
        ChangeNotifierProvider<ProgressService>.value(value: progress),
      ],
    );

    expect(find.text('Major 7'), findsOneWidget);
    expect(find.text('Half-diminished'), findsOneWidget);
  });

  test('each quality has the right intervals (voiced by chord_quality)', () {
    expect(SeventhKind.major7.intervals, [0, 4, 7, 11]);
    expect(SeventhKind.dominant7.intervals, [0, 4, 7, 10]);
    expect(SeventhKind.minor7.intervals, [0, 3, 7, 10]);
    expect(SeventhKind.halfDim7.intervals, [0, 3, 6, 10]);
  });
}
