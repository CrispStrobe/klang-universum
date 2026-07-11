import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/songs/song_book.dart';
import 'package:klang_universum/features/games/songs/song_screen.dart';
import 'package:klang_universum/features/games/songs/tune_quiz_screen.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:partitura/partitura.dart' show MultiSystemView;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child, SriService sri) {
  return MultiProvider(
    providers: [
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
      expect(score.lyrics.length, song.playback.length,
          reason: '${song.id}: one syllable per note in these songs');

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

  testWidgets('tune quiz offers all song titles and records',
      (tester) async {
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
}
