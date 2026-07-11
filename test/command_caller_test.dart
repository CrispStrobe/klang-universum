// Follow the Conductor — the reaction/gesture toy. Verifies that performing the
// called gesture scores, and that letting the countdown bar empty costs a life.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/settings_service.dart';
import 'package:klang_universum/features/games/scales/command_caller_screen.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app() => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
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
        home: CommandCallerScreen(),
      ),
    );

CommandCallerTester _game(WidgetTester tester) =>
    tester.state<State<CommandCallerScreen>>(find.byType(CommandCallerScreen))
        as CommandCallerTester;

/// Perform the gesture that satisfies command [key] on the pad.
Future<void> _do(WidgetTester tester, String key) async {
  final pad = find.byKey(CommandCallerScreen.padKey);
  switch (key) {
    case 'tap':
      await tester.tap(pad);
    case 'hold':
      await tester.longPress(pad);
    case 'swipeLeft':
      await tester.drag(pad, const Offset(-140, 0));
    case 'swipeRight':
      await tester.drag(pad, const Offset(140, 0));
    case 'swipeUp':
      await tester.drag(pad, const Offset(0, -140));
    case 'swipeDown':
      await tester.drag(pad, const Offset(0, 140));
  }
  await tester.pump();
}

/// Let the run play out (doing nothing → timeouts → game over) so no round
/// timer is left pending at teardown.
Future<void> _drain(WidgetTester tester, CommandCallerTester game) async {
  for (var i = 0; i < 80 && !game.finished; i++) {
    await tester.pump(const Duration(milliseconds: 700));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('performing the called gesture scores a point', (tester) async {
    await tester.pumpWidget(_app());
    final game = _game(tester);

    final key = game.currentCommandKey;
    expect(key, isNotNull);

    await _do(tester, key!);
    expect(game.score, greaterThan(0));
    expect(game.lives, CommandCallerScreen.maxLives);

    await _drain(tester, game);
  });

  testWidgets('letting the bar empty costs a life', (tester) async {
    await tester.pumpWidget(_app());
    final game = _game(tester);
    expect(game.currentCommandKey, isNotNull);

    // Do nothing until past the (max) countdown window.
    await tester.pump(const Duration(milliseconds: 2700));
    expect(game.lives, lessThan(CommandCallerScreen.maxLives));
    expect(game.score, 0);

    await _drain(tester, game);
  });
}
