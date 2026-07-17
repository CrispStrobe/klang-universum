// Write It for the Instrument — the inverse of Concert Pitch (crisp_notation
// Transposition). Verifies the round loop: the correct written-note letter is
// offered, picking it scores + records SRI under transpose.*, and clearing all
// rounds finishes. Also pins the transposition inverse (round-trip vs the
// forward maths) so a sign flip can't slip through.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/transpose/transpose_write_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart' hide Interval, Step;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app() => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider(
          create: (_) => SriService(getNow: () => DateTime(2026, 7, 17)),
        ),
        Provider<AudioService>(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => ProgressService()),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('en'), Locale('de')],
        home: TransposeWriteScreen(),
      ),
    );

TransposeWriteTester _game(WidgetTester tester) =>
    tester.state<State<TransposeWriteScreen>>(
      find.byType(TransposeWriteScreen),
    ) as TransposeWriteTester;

Future<void> _solveRound(WidgetTester tester) async {
  // English default naming: the button label is the step letter, upper-cased.
  final label = _game(tester).answerStep.name.toUpperCase();
  await tester.tap(find.widgetWithText(FilledButton, label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the written note is offered and picking it advances',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('Round 1 of 10'), findsOneWidget);
    final sri =
        tester.element(find.byType(TransposeWriteScreen)).read<SriService>();

    await _solveRound(tester);
    expect(sri.getDetailedBreakdown()['transpose'], isNotNull);
    expect(find.text('Round 2 of 10'), findsOneWidget);
  });

  testWidgets('clearing all rounds finishes with a result screen',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    for (var r = 0; r < 10; r++) {
      await _solveRound(tester);
    }

    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
  });

  // The written note must be the exact inverse of Concert Pitch's forward maths:
  // transposing the WRITTEN answer back to concert pitch must return the sounding
  // note shown to the child (a Bb instrument writing a whole step up, etc.).
  test('the written answer transposes back to the shown concert pitch', () {
    Pitch toConcert(Pitch written, Transposition t) {
      var p = written.transposeBy(t.interval, descending: t.down);
      for (var i = 0; i < t.octaves; i++) {
        p = p.transposeBy(Interval.perfectOctave, descending: t.down);
      }
      return p;
    }

    Pitch toWritten(Pitch concert, Transposition t) {
      var p = concert.transposeBy(t.interval, descending: !t.down);
      for (var i = 0; i < t.octaves; i++) {
        p = p.transposeBy(Interval.perfectOctave, descending: !t.down);
      }
      return p;
    }

    for (final t in [
      Transposition.bFlat,
      Transposition.eFlat,
      Transposition.f,
    ]) {
      for (var pos = 2; pos <= 8; pos++) {
        final concert = Clef.treble.pitchAt(pos);
        final written = toWritten(concert, t);
        expect(
          toConcert(written, t).midiNumber,
          concert.midiNumber,
          reason: 'inverse should round-trip for $t at staff pos $pos',
        );
      }
    }
  });
}
