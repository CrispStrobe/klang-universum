// Label the Form — the section-shape game.
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/composition/form_read_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/game_test_support.dart';

FormReadTester _g(WidgetTester t) =>
    t.state<State<FormReadScreen>>(find.byType(FormReadScreen))
        as FormReadTester;

Future<void> _answer(WidgetTester t) async {
  await t.tap(find.widgetWithText(FilledButton, _g(t).answer).first);
  await t.pump(const Duration(milliseconds: 800));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('offers form options and records under composition.form',
      (t) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 17));
    await pumpGame(t, const FormReadScreen(), sri: sri);
    // The correct form string is one of the offered buttons.
    expect(find.widgetWithText(FilledButton, _g(t).answer), findsWidgets);
    await _answer(t);
    expect(sri.getDetailedBreakdown()['composition']!.keys, ['form']);
  });

  testWidgets('clearing all rounds finishes', (t) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 17));
    await pumpGame(t, const FormReadScreen(), sri: sri);
    for (var i = 0; i < 10 && !_g(t).isFinished; i++) {
      await _answer(t);
    }
    expect(_g(t).isFinished, isTrue);
  });
}
