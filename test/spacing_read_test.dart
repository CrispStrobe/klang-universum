// Close or Open? — read SATB spacing. Two layers: (1) the voicing generator puts
// soprano and tenor within an octave for close and beyond an octave for open,
// across all keys/degrees; (2) the game is driven through the UI — tap the
// Close/Open button the game reports as the answer.

import 'dart:math';

import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/satb_voicing.dart';
import 'package:comet_beat/features/games/note_reading/spacing_read_screen.dart';
import 'package:crisp_notation/crisp_notation.dart' show StaffSystemView;
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

SpacingReadTester _game(WidgetTester tester) =>
    tester.state<State<SpacingReadScreen>>(find.byType(SpacingReadScreen))
        as SpacingReadTester;

int _midiOf(SpacingChord c, SatbVoice v) =>
    c.parts.firstWhere((p) => p.voice == v).pitch.midiNumber;

Future<void> _answerCorrectly(WidgetTester tester) async {
  final label = _game(tester).isOpen ? 'Open' : 'Close';
  await tester.tap(find.widgetWithText(FilledButton, label));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('voicing invariant', () {
    for (final wide in [false, true]) {
      test('close ≤ octave, open > octave (wide=$wide)', () {
        final random = Random(42);
        for (var i = 0; i < 200; i++) {
          final close = voiceSpacing(random, open: false, wide: wide);
          final open = voiceSpacing(random, open: true, wide: wide);

          // Four distinct voices, each a real pitch.
          expect(close.parts.map((p) => p.voice).toSet().length, 4);

          final closeSpan = _midiOf(close, SatbVoice.soprano) -
              _midiOf(close, SatbVoice.tenor);
          final openSpan =
              _midiOf(open, SatbVoice.soprano) - _midiOf(open, SatbVoice.tenor);

          expect(closeSpan, greaterThan(0));
          expect(
            closeSpan,
            lessThanOrEqualTo(12),
            reason: 'close position keeps S–T within an octave',
          );
          expect(
            openSpan,
            greaterThan(12),
            reason: 'open position spreads S–T beyond an octave',
          );

          // Voices never cross: S ≥ A ≥ T ≥ B.
          expect(
            _midiOf(close, SatbVoice.soprano),
            greaterThanOrEqualTo(_midiOf(close, SatbVoice.alto)),
          );
          expect(
            _midiOf(close, SatbVoice.alto),
            greaterThanOrEqualTo(_midiOf(close, SatbVoice.tenor)),
          );
          expect(
            _midiOf(close, SatbVoice.tenor),
            greaterThanOrEqualTo(_midiOf(close, SatbVoice.bass)),
          );
        }
      });
    }
  });

  testWidgets('shows the chord and records under note_reading.spacing',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 17));
    await pumpGame(tester, const SpacingReadScreen(), sri: sri);

    expect(find.byType(StaffSystemView), findsOneWidget);

    await _answerCorrectly(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(sri.getDetailedBreakdown()['note_reading']!.keys, ['spacing']);
  });

  testWidgets('clearing all ten rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 17));
    await pumpGame(tester, const SpacingReadScreen(), sri: sri);

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await _answerCorrectly(tester);
      await tester.pump(const Duration(seconds: 1));
    }

    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
    await tester.pump(const Duration(seconds: 1));
  });
}
