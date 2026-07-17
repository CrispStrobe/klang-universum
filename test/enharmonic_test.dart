// Enharmonic Twins — the same-sound-spelled-two-ways reading drill. A staff card
// is shown, so the shared game surface is used; we tap the correct Same/Different
// button per the game's own report of the answer, and pin the core invariant:
// "same sound" is true exactly when the two notes share a MIDI number.

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/enharmonic_screen.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

EnharmonicTester _game(WidgetTester tester) =>
    tester.state<State<EnharmonicScreen>>(find.byType(EnharmonicScreen))
        as EnharmonicTester;

Future<void> _answerCorrectly(WidgetTester tester) async {
  final label = _game(tester).answerSame ? 'Same sound' : 'Different';
  await tester.tap(find.text(label));
  await tester.pump(const Duration(milliseconds: 800)); // auto-advance
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('offers Same / Different and records under reading.enharmonic',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 17));
    await pumpGame(tester, const EnharmonicScreen(), sri: sri);

    expect(find.text('Same sound'), findsOneWidget);
    expect(find.text('Different'), findsOneWidget);

    await _answerCorrectly(tester);
    expect(sri.getDetailedBreakdown()['reading']!.keys, ['enharmonic']);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 17));
    await pumpGame(tester, const EnharmonicScreen(), sri: sri);

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answerCorrectly(tester);
    }
    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });

  testWidgets('the claimed answer always matches the sounding pitch',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 17));
    await pumpGame(tester, const EnharmonicScreen(), sri: sri);

    // The whole drill rests on this: "same sound" is true iff the two notes
    // share a MIDI number (an accidental enharmonic match can never sneak into a
    // "different" round, nor a real difference into a "same" round).
    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      final g = _game(tester);
      expect(g.answerSame, g.notesShareMidi);
      await _answerCorrectly(tester);
    }
  });
}
