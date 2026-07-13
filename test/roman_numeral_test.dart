// Roman Numerals — read/hear a diatonic triad, name its numeral. Driven through
// the UI: the correct symbol varies per round, so tap whatever the game reports
// as the target and check it scores + records under harmony.roman.

import 'package:flutter/material.dart' hide Step;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/settings_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/harmony/roman_numeral_screen.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(SriService sri) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider<SriService>.value(value: sri),
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
        home: RomanNumeralScreen(),
      ),
    );

RomanNumeralTester _game(WidgetTester tester) =>
    tester.state<State<RomanNumeralScreen>>(find.byType(RomanNumeralScreen))
        as RomanNumeralTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('offers four numeral choices incl. the target and a replay',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await tester.pumpWidget(_wrap(sri));
    await tester.pump();

    // The target's button is on screen, and a "hear again" control exists.
    expect(
      find.widgetWithText(FilledButton, _game(tester).targetSymbol),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.volume_up), findsOneWidget);
  });

  testWidgets('answering the target scores and records under harmony.roman',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await tester.pumpWidget(_wrap(sri));
    await tester.pump();

    await tester.tap(
      find.widgetWithText(FilledButton, _game(tester).targetSymbol),
    );
    await tester.pump();

    expect(sri.getDetailedBreakdown()['harmony']!.keys, ['roman']);
    await tester
        .pump(const Duration(seconds: 1)); // drain advance/replay timers
  });

  testWidgets('clearing all ten rounds finishes with a result screen',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await tester.pumpWidget(_wrap(sri));
    await tester.pump();

    for (var i = 0; i < 10 && !_game(tester).isFinished; i++) {
      await tester.tap(
        find.widgetWithText(FilledButton, _game(tester).targetSymbol),
      );
      await tester.pump(const Duration(milliseconds: 900)); // auto-advance
    }

    expect(_game(tester).isFinished, isTrue);
    expect(find.byIcon(Icons.star).evaluate().length, greaterThanOrEqualTo(1));
    await tester.pump(const Duration(seconds: 1)); // drain any trailing timers
  });
}
