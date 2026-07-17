// On the Beat or Off? — the syncopation reading drill.
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/measures/sync_read_screen.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/game_test_support.dart';

SyncReadTester _g(WidgetTester t) =>
    t.state<State<SyncReadScreen>>(find.byType(SyncReadScreen))
        as SyncReadTester;

Future<void> _answer(WidgetTester t) async {
  await t.tap(find.text(_g(t).answerSyncopated ? 'Syncopated' : 'On the beat'));
  await t.pump(const Duration(milliseconds: 800));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('offers the two answers and records under measures.syncopation',
      (t) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 17));
    await pumpGame(t, const SyncReadScreen(), sri: sri);
    expect(find.text('On the beat'), findsOneWidget);
    expect(find.text('Syncopated'), findsOneWidget);
    await _answer(t);
    expect(sri.getDetailedBreakdown()['measures']!.keys, ['syncopation']);
  });

  testWidgets('clearing all rounds finishes', (t) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 17));
    await pumpGame(t, const SyncReadScreen(), sri: sri);
    for (var i = 0; i < 10 && !_g(t).isFinished; i++) {
      await _answer(t);
    }
    expect(_g(t).isFinished, isTrue);
  });
}
