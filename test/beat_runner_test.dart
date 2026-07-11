// Beat Runner — the tap-along rhythm lane. The game's Ticker is the master
// clock, driven by tester.pump(): tapping when a beat reaches the line scores,
// and letting a beat pass untapped does not.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/settings_service.dart';
import 'package:klang_universum/features/games/measures/beat_runner_screen.dart';
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
        home: BeatRunnerScreen(),
      ),
    );

BeatRunnerTester _game(WidgetTester tester) =>
    tester.state<State<BeatRunnerScreen>>(find.byType(BeatRunnerScreen))
        as BeatRunnerTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tapping as the beat lands scores a hit', (tester) async {
    await tester.pumpWidget(_app());
    final game = _game(tester);

    // Advance the master clock to the moment beat 0 crosses the line.
    await tester.pump(Duration(milliseconds: BeatRunnerScreen.beatTimeMs(0)));
    await tester.tap(find.byKey(BeatRunnerScreen.padKey));
    await tester.pump();

    expect(game.hits, 1);
    expect(game.score, greaterThan(0));
  });

  testWidgets('letting a beat pass untapped is not a hit', (tester) async {
    await tester.pumpWidget(_app());
    final game = _game(tester);

    // Past beat 0's window with no tap.
    await tester.pump(
      Duration(milliseconds: BeatRunnerScreen.beatTimeMs(0) + 260),
    );
    expect(game.hits, 0);
    expect(game.score, 0);
  });
}
