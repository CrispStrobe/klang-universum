// Power Chords (power_chord) — name the two-note root+fifth shape.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/guitar/power_chord_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget home, SriService sri) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider<SriService>.value(value: sri),
        Provider<AudioService>(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => ProgressService()),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('de')],
        home: home,
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the shape (R + 5) and four name choices', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const PowerChordScreen(),
        SriService(getNow: () => DateTime(2026, 7, 19)),
      ),
    );
    await tester.pump();
    expect(find.text('R'), findsOneWidget); // the root dot (unique)
    expect(find.text('5'), findsWidgets); // the fifth dot (+ the fret-5 header)
    expect(find.byType(FilledButton), findsNWidgets(4)); // four name choices
  });

  testWidgets('tapping a choice records under guitar.power and advances',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 19));
    await tester.pumpWidget(_wrap(const PowerChordScreen(), sri));
    await tester.pump();

    await tester.tap(find.byType(FilledButton).first);
    await tester.pump();

    expect(sri.totalTrackedItems, 1);
    expect(sri.getDetailedBreakdown()['guitar']!.keys, contains('power'));
    await tester.pumpAndSettle();
  });
}
