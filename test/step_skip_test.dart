// Step or Skip? — the melodic-motion reading drill. A staff card is shown, so
// the shared game surface is used; we tap the correct Step/Skip button per the
// game's own report of the answer.

import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/note_reading/step_skip_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

StepSkipTester _game(WidgetTester tester) =>
    tester.state<State<StepSkipScreen>>(find.byType(StepSkipScreen))
        as StepSkipTester;

Future<void> _answerCorrectly(WidgetTester tester) async {
  final label = _game(tester).answerStep ? 'Step' : 'Skip';
  await tester.tap(find.text(label));
  await tester.pump(const Duration(milliseconds: 800)); // auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('offers Step / Skip and records under reading.motion',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const StepSkipScreen(), sri: sri);

    expect(find.text('Step'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);

    await _answerCorrectly(tester);
    expect(sri.getDetailedBreakdown()['reading']!.keys, ['motion']);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await pumpGame(tester, const StepSkipScreen(), sri: sri);

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answerCorrectly(tester);
    }
    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
