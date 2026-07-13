// Composition Workshop — the touch-first score editor shell. Verifies it
// renders the score canvas + bottom input dock (piano), places notes by tapping
// the staff, auto-bars per the time signature, adds rests, and undoes/redoes.

import 'package:flutter/material.dart' hide Step;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/settings_service.dart';
import 'package:klang_universum/features/games/songs/user_songs_service.dart';
import 'package:klang_universum/features/workshop/screens/composition_workshop_screen.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/widgets/piano_keyboard.dart';
import 'package:partitura/partitura.dart' show InteractiveStaff;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app() => MultiProvider(
      providers: [
        Provider<AudioService>(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => UserSongsService()),
        ChangeNotifierProvider(create: (_) => SettingsService()),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('en'), Locale('de')],
        home: CompositionWorkshopScreen(),
      ),
    );

CompositionWorkshopTester _editor(WidgetTester tester) =>
    tester.state<State<CompositionWorkshopScreen>>(
      find.byType(CompositionWorkshopScreen),
    ) as CompositionWorkshopTester;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
  }

  testWidgets('renders the score canvas and the piano input dock',
      (tester) async {
    await pump(tester);
    expect(find.byType(InteractiveStaff), findsOneWidget);
    expect(find.byType(PianoKeyboard), findsOneWidget);
  });

  testWidgets(
      'tapping the staff writes notes; bars fill per the time signature',
      (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    expect(editor.noteCount, 0);
    expect(editor.barCount, 1); // an empty rest bar

    // Default value is a quarter; place five of them in 4/4 → a second bar.
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byType(InteractiveStaff), warnIfMissed: false);
      await tester.pump();
    }
    expect(editor.noteCount, 5);
    expect(editor.barCount, 2, reason: '4 quarters fill a 4/4 bar');
  });

  testWidgets('the rest button adds a rest element', (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    await tester.tap(find.byIcon(Icons.music_off_outlined));
    await tester.pump();
    expect(editor.noteCount, 1);
  });

  testWidgets('undo then redo round-trips a placed note', (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    await tester.tap(find.byType(InteractiveStaff), warnIfMissed: false);
    await tester.pump();
    expect(editor.noteCount, 1);

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(editor.noteCount, 0);

    await tester.tap(find.byIcon(Icons.redo));
    await tester.pump();
    expect(editor.noteCount, 1);
  });
}
