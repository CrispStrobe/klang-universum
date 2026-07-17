// Even or Triplet? — the beat-subdivision reading drill (uses a real TupletSpan).
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_values/triplet_read_screen.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/game_test_support.dart';

TripletReadTester _g(WidgetTester t) =>
    t.state<State<TripletReadScreen>>(find.byType(TripletReadScreen))
        as TripletReadTester;

Future<void> _answer(WidgetTester t) async {
  await t.tap(find.text(_g(t).answerTriplet ? 'Triplet (3)' : 'Even (2)'));
  await t.pump(const Duration(milliseconds: 800));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('offers even/triplet and records under note_values.tuplet',
      (t) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 17));
    await pumpGame(t, const TripletReadScreen(), sri: sri);
    expect(find.text('Even (2)'), findsOneWidget);
    expect(find.text('Triplet (3)'), findsOneWidget);
    await _answer(t);
    expect(sri.getDetailedBreakdown()['note_values']!.keys, ['tuplet']);
  });

  testWidgets('clearing all rounds finishes', (t) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 17));
    await pumpGame(t, const TripletReadScreen(), sri: sri);
    for (var i = 0; i < 10 && !_g(t).isFinished; i++) {
      await _answer(t);
    }
    expect(_g(t).isFinished, isTrue);
  });
}
