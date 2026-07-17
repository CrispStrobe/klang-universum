// Which Mode? — the three-way modal ear game (Major / Minor / Dorian). No staff,
// so a plain provider tree is enough; we tap the button matching the game's own
// report of the answer.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/scales/mode_ear_screen.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

ModeEarTester _game(WidgetTester tester) =>
    tester.state<State<ModeEarScreen>>(find.byType(ModeEarScreen))
        as ModeEarTester;

String _labelFor(Mode m) => switch (m) {
      Mode.major => 'Major',
      Mode.minor => 'Minor',
      Mode.dorian => 'Dorian',
    };

Future<void> _answerCorrectly(WidgetTester tester) async {
  await tester.tap(find.text(_labelFor(_game(tester).answer)));
  await tester.pump(const Duration(milliseconds: 800)); // clear auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('offers Major / Minor / Dorian and records under scales.mode',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 17));
    await pumpGame(tester, const ModeEarScreen(), sri: sri);

    expect(find.text('Major'), findsOneWidget);
    expect(find.text('Minor'), findsOneWidget);
    expect(find.text('Dorian'), findsOneWidget);

    await _answerCorrectly(tester);
    expect(sri.getDetailedBreakdown()['scales']!.keys, ['mode']);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 17));
    await pumpGame(tester, const ModeEarScreen(), sri: sri);

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answerCorrectly(tester);
    }
    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });
}
