// The shared compact keyboard (B1) — it builds, scrolls, and taps report MIDI.

import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/piano_keyboard.dart';
import 'package:comet_beat/shared/widgets/scrollable_piano.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('de')],
      home: ChangeNotifierProvider(
        create: (_) => SettingsService(),
        child: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('builds a wide, scrollable keyboard and reports tapped MIDI',
      (tester) async {
    int? tapped;
    await tester.pumpWidget(
      _wrap(ScrollablePiano(onKeyTap: (m) => tapped = m)),
    );
    await tester.pump();

    // It hosts a PianoKeyboard inside a horizontal scroll view.
    expect(find.byType(PianoKeyboard), findsOneWidget);
    final scroll = find.byType(SingleChildScrollView);
    expect(scroll, findsOneWidget);
    expect(
      tester.widget<SingleChildScrollView>(scroll).scrollDirection,
      Axis.horizontal,
    );

    // The keyboard is wider than the viewport (many octaves → scrollable).
    final kbWidth = tester.getSize(find.byType(PianoKeyboard)).width;
    expect(kbWidth, greaterThan(tester.getSize(find.byType(Scaffold)).width));

    // Tapping a key reports its MIDI.
    await tester.tap(find.byType(PianoKeyboard), warnIfMissed: false);
    expect(tapped, isNotNull);
  });
}
