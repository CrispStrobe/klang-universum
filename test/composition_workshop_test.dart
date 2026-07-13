// Composition Workshop — the touch-first score editor shell. Verifies it
// renders the multi-line score canvas + bottom input dock (piano), adds rests,
// and undoes/redoes. Note placement (from the piano) is covered by the
// ScoreDocument model tests.

import 'package:flutter/material.dart' hide Step;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/settings_service.dart';
import 'package:klang_universum/features/games/songs/user_songs_service.dart';
import 'package:klang_universum/features/workshop/screens/composition_workshop_screen.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/widgets/piano_keyboard.dart';
import 'package:partitura/partitura.dart'
    show InteractiveGrandStaffView, MultiSystemView;
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
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
  }

  testWidgets('renders the multi-line canvas and the piano input dock',
      (tester) async {
    await pump(tester);
    expect(find.byType(MultiSystemView), findsOneWidget);
    expect(find.byType(PianoKeyboard), findsOneWidget);
  });

  testWidgets('the rest button adds a rest; bars fill per the meter',
      (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    expect(editor.noteCount, 0);
    expect(editor.barCount, 1); // an empty rest bar

    // Default value is a quarter; five rests in 4/4 → a second bar.
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byIcon(Icons.music_off_outlined));
      await tester.pump();
    }
    expect(editor.noteCount, 5);
    expect(editor.barCount, 2, reason: '4 quarters fill a 4/4 bar');
  });

  testWidgets('undo then redo round-trips an added element', (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    await tester.tap(find.byIcon(Icons.music_off_outlined));
    await tester.pump();
    expect(editor.noteCount, 1);

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(editor.noteCount, 0);

    await tester.tap(find.byIcon(Icons.redo));
    await tester.pump();
    expect(editor.noteCount, 1);
  });

  testWidgets('tapping the piano places a note and selects it', (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    await tester.tap(find.byType(PianoKeyboard));
    await tester.pump();
    expect(editor.noteCount, 1);
    expect(editor.hasSelection, isTrue);
  });

  testWidgets('copy then paste duplicates the selection', (tester) async {
    await pump(tester);
    final editor = _editor(tester);
    await tester.tap(find.byType(PianoKeyboard));
    await tester.pump();
    expect(editor.noteCount, 1);

    await tester.tap(find.byIcon(Icons.copy));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.content_paste));
    await tester.pump();
    expect(editor.noteCount, 2);
  });

  testWidgets('the overflow menu offers open and export', (tester) async {
    await pump(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.importMusicXmlFile), findsOneWidget);
    expect(find.text(l10n.workshopExportXml), findsOneWidget);
  });

  testWidgets('the note palette offers articulations and dynamics',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byType(PianoKeyboard)); // places + selects a note
    await tester.pump();
    await tester.tap(find.byIcon(Icons.expand_less)); // the palette button
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.workshopStaccato), findsOneWidget);
    expect(find.textContaining('mf'), findsWidgets); // a dynamic entry
  });

  testWidgets('switching to grand-staff mode shows both clefs', (tester) async {
    await pump(tester);
    expect(find.byType(MultiSystemView), findsOneWidget);
    // Open the staff-mode dropdown (currently the treble glyph) and pick grand.
    await tester.tap(find.text('𝄞').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('𝄞𝄢').last);
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveGrandStaffView), findsOneWidget);
    expect(find.byType(MultiSystemView), findsNothing);
  });
}
