// Which Ornament? — the trill/mordent/turn reading drill.
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/ornament_read_screen.dart';
import 'package:crisp_notation/crisp_notation.dart' show Ornament;
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/game_test_support.dart';

OrnamentReadTester _g(WidgetTester t) =>
    t.state<State<OrnamentReadScreen>>(find.byType(OrnamentReadScreen))
        as OrnamentReadTester;

Future<void> _answer(WidgetTester t) async {
  final label = switch (_g(t).answer) {
    Ornament.trill => 'Trill',
    Ornament.mordent => 'Mordent',
    _ => 'Turn',
  };
  await t.tap(find.text(label));
  await t.pump(const Duration(milliseconds: 800));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'offers trill/mordent/turn and records under note_reading.ornament',
      (t) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 17));
    await pumpGame(t, const OrnamentReadScreen(), sri: sri);
    expect(find.text('Trill'), findsOneWidget);
    expect(find.text('Mordent'), findsOneWidget);
    expect(find.text('Turn'), findsOneWidget);
    await _answer(t);
    expect(sri.getDetailedBreakdown()['note_reading']!.keys, ['ornament']);
  });

  testWidgets('clearing all rounds finishes', (t) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 17));
    await pumpGame(t, const OrnamentReadScreen(), sri: sri);
    for (var i = 0; i < 10 && !_g(t).isFinished; i++) {
      await _answer(t);
    }
    expect(_g(t).isFinished, isTrue);
  });
}
