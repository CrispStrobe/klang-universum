import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/songs/chord_sheet_screen.dart';
import 'package:klang_universum/features/games/songs/import/chordpro.dart';
import 'package:klang_universum/features/games/songs/import_screen.dart';
import 'package:klang_universum/features/games/songs/song_book.dart';
import 'package:klang_universum/features/games/songs/song_screen.dart';
import 'package:klang_universum/features/games/songs/tune_quiz_screen.dart';
import 'package:klang_universum/features/games/songs/user_songs_service.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:partitura/partitura.dart' show MultiSystemView;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _xml = '''
<score-partwise version="4.0"><part-list><score-part id="P1">
<part-name>M</part-name></score-part></part-list><part id="P1"><measure number="1">
<attributes><divisions>1</divisions><key><fifths>0</fifths></key>
<time><beats>4</beats><beat-type>4</beat-type></time>
<clef><sign>G</sign><line>2</line></clef></attributes>
<note><pitch><step>C</step><octave>4</octave></pitch><duration>4</duration>
<type>whole</type></note></measure></part></score-partwise>''';

Widget _wrap(Widget child, SriService sri, {UserSongsService? songs}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SriService>.value(value: sri),
      Provider<AudioService>(create: (_) => AudioService()),
      ChangeNotifierProvider(create: (_) => ProgressService()),
      ChangeNotifierProvider<UserSongsService>.value(
        value: songs ?? UserSongsService(),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('de')],
      home: child,
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('every song parses: lyrics align with notes, playback is sane', () {
    for (final song in kSongs) {
      // Building the score throws if lyric tokens do not match the notes.
      final score = song.score;
      expect(score.lyrics, isNotEmpty, reason: song.id);
      expect(
        score.lyrics.length,
        song.playback.length,
        reason: '${song.id}: one syllable per note in these songs',
      );

      final playback = song.playback;
      expect(playback.length, greaterThan(10 - 1), reason: song.id);
      for (final (id, midi, ms) in playback) {
        expect(id, isNotEmpty);
        expect(midi, inInclusiveRange(48, 84), reason: song.id);
        expect(ms, greaterThan(0));
      }
    }
  });

  testWidgets('song book lists all songs; song screen renders systems',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await tester.pumpWidget(_wrap(const SongListScreen(), sri));
    await tester.pump();

    for (final song in kSongs) {
      expect(find.text(song.title), findsOneWidget);
    }

    await tester.tap(find.text('Alle meine Entchen'));
    await tester.pumpAndSettle();

    expect(find.byType(MultiSystemView), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tune quiz offers all song titles and records', (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    await tester.pumpWidget(_wrap(const TuneQuizScreen(), sri));
    await tester.pump();

    expect(find.textContaining('Which song'), findsOneWidget);
    for (final song in kSongs) {
      expect(find.text(song.title), findsOneWidget);
    }

    await tester.tap(find.text(kSongs.first.title));
    await tester.pump();
    expect(sri.getDetailedBreakdown()['songs']!.keys, ['tune']);
    await tester.pumpAndSettle();
  });

  testWidgets('chord sheet screen renders the chord row and lyrics',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    final sheet = parseChordPro('{title: Test}\n[C]Twin- kle [G]twin- kle');
    await tester.pumpWidget(
      _wrap(ChordSheetScreen(title: 'Test', sheet: sheet), sri),
    );
    await tester.pump();

    expect(find.widgetWithText(AppBar, 'Test'), findsOneWidget);
    expect(find.byType(ActionChip), findsWidgets); // the strum row
    expect(find.text('C'), findsWidgets);
    expect(find.textContaining('Twin'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('import screen: pasted MusicXML lands in the Song Book',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 11));
    final songs = UserSongsService();
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ImportScreen()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        sri,
        songs: songs,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // All four import affordances are present.
    expect(find.text('Import as MusicXML'), findsOneWidget);
    expect(find.text('Pick a MusicXML file…'), findsOneWidget);
    expect(find.text('Pick a MIDI file…'), findsOneWidget);

    // Paste valid MusicXML and import it.
    await tester.enterText(find.byType(TextField).last, _xml);
    await tester.tap(find.text('Import as MusicXML'));
    await tester.pumpAndSettle();

    expect(songs.songs, hasLength(1));
    expect(find.text('open'), findsOneWidget); // popped back
  });
}
