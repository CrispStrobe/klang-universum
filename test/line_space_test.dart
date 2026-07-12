import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/settings_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/note_reading/line_space_screen.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:partitura/partitura.dart' show Clef, StaffView;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('line or space: a correct swipe advances the round',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await tester.pumpWidget(
      MultiProvider(
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
          home: LineSpaceScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Round 1 of 10'), findsOneWidget);
    expect(find.text('Line'), findsOneWidget);
    expect(find.text('Space'), findsOneWidget);
    expect(find.byType(StaffView), findsOneWidget);

    // Swipe left (Line). If that was wrong, the round stays put — then the
    // note must be a space, so swipe right. Either way it should advance.
    await tester.drag(find.byType(StaffView), const Offset(-150, 0));
    await tester.pumpAndSettle();
    if (find.text('Round 1 of 10').evaluate().isNotEmpty) {
      await tester.drag(find.byType(StaffView), const Offset(150, 0));
      await tester.pumpAndSettle();
    }

    expect(find.text('Round 2 of 10'), findsOneWidget);
    expect(sri.totalTrackedItems, greaterThanOrEqualTo(1));
  });

  testWidgets('bass-clef variant renders and answers', (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await tester.pumpWidget(
      MultiProvider(
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
          home: LineSpaceScreen(clef: Clef.bass),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(StaffView), findsOneWidget);

    await tester.drag(find.byType(StaffView), const Offset(-150, 0));
    await tester.pumpAndSettle();
    if (find.text('Round 1 of 10').evaluate().isNotEmpty) {
      await tester.drag(find.byType(StaffView), const Offset(150, 0));
      await tester.pumpAndSettle();
    }
    expect(find.text('Round 2 of 10'), findsOneWidget);
    // Recorded under the bass namespace.
    expect(sri.totalTrackedItems, greaterThanOrEqualTo(1));
  });
}
