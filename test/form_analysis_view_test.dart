// The AnaVis-style form-analysis view: worked form examples shown as a coloured,
// tappable section timeline you can play. Also covers the textbook's per-concept
// prose lookup (conceptProse).
import 'package:comet_beat/core/curriculum/concept_map.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/games/composition/form_analysis_view.dart';
import 'package:comet_beat/features/games/composition/form_timeline.dart';
import 'package:comet_beat/features/games/widgets/playing_staff.dart';
import 'package:comet_beat/features/textbook/textbook_i18n.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart' show NoteElement, StaffView;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _app(Widget home, {Locale locale = const Locale('en')}) => MultiProvider(
      providers: [Provider<AudioService>(create: (_) => AudioService())],
      child: MaterialApp(
        locale: locale,
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
  group('form example data', () {
    test('the form concepts each carry worked examples', () {
      expect(kFormExamples['musical_form'], isNotNull);
      expect(kFormExamples['song_form'], isNotNull);
      // Ternary is A-B-A; the rondo returns to A between new tunes.
      expect(kFormExamples['musical_form']!.first.pattern, ['A', 'B', 'A']);
      expect(
        kFormExamples['musical_form']!.last.pattern,
        ['A', 'B', 'A', 'C', 'A'],
      );
    });

    test('the whole phrase is every section end to end', () {
      final ex = kFormExamples['musical_form']!.first; // A-B-A, 4 notes each
      expect(ex.sectionPhrase(0).length, 4);
      expect(ex.wholePhrase.length, ex.pattern.length * 4);
      // Section A and the recap share the same motif.
      expect(ex.sectionPhrase(0), ex.sectionPhrase(2));
      expect(ex.sectionPhrase(0), isNot(ex.sectionPhrase(1)));
    });

    test('the engraved score is one bar per section with unique ids', () {
      final ex = kFormExamples['musical_form']!.last; // A-B-A-C-A → 5 bars
      final score = ex.scoreOf();
      expect(score.measures.length, ex.pattern.length);
      final ids = <String?>{};
      for (final m in score.measures) {
        for (final e in m.elements) {
          expect(ids.add((e as NoteElement).id), isTrue, reason: 'dup id');
        }
      }
    });
  });

  group('harmony example data', () {
    test('the harmony concepts carry function-coloured progressions', () {
      expect(kHarmonyExamples['harmonic_function'], isNotNull);
      expect(kHarmonyExamples['cadences'], isNotNull);
      // I–IV–V–I walks home → away → tension → home.
      final auth = kHarmonyExamples['harmonic_function']!.first;
      expect(auth.chords.map((c) => c.function).toList(), [
        HarmonyFunction.tonic,
        HarmonyFunction.subdominant,
        HarmonyFunction.dominant,
        HarmonyFunction.tonic,
      ]);
      // A perfect cadence ends on the tonic; a half cadence on the dominant.
      final cads = kHarmonyExamples['cadences']!;
      expect(cads.first.chords.last.function, HarmonyFunction.tonic);
      expect(cads.last.chords.last.function, HarmonyFunction.dominant);
      // Every chord is a real triad.
      for (final ex in kHarmonyExamples.values.expand((l) => l)) {
        for (final c in ex.chords) {
          expect(c.midis.length, 3);
        }
      }
    });

    test('the engraved progression is one whole-note chord per bar', () {
      final ex = kHarmonyExamples['harmonic_function']!.first; // 4 chords
      final score = ex.scoreOf();
      expect(score.measures.length, ex.chords.length);
      for (var i = 0; i < ex.chords.length; i++) {
        final note = score.measures[i].elements.single as NoteElement;
        expect(note.pitches.length, 3); // a triad, stacked
      }
    });

    test('cadence examples carry a cadence marker, function examples do not',
        () {
      for (final ex in kHarmonyExamples['cadences']!) {
        expect(ex.cadence, isNotNull);
      }
      for (final ex in kHarmonyExamples['harmonic_function']!) {
        expect(ex.cadence, isNull);
      }
    });
  });

  group('playback highlight schedule', () {
    test('a form schedule lines up one step per engraved note id', () {
      final ex = kFormExamples['musical_form']!.last; // A-B-A-C-A
      final ids = ex.wholeSteps().expand((s) => s.ids).toList();
      // ids run n0, n1, … in engraving order (matching scoreOf()).
      expect(ids, [for (var i = 0; i < ids.length; i++) 'n$i']);
      // Section 1 (the B) starts right after section 0's four notes.
      expect(ex.sectionSteps(1).first.ids, {'n4'});
    });

    test('a harmony schedule lights one chord id at a time', () {
      final ex = kHarmonyExamples['harmonic_function']!.first; // 4 chords
      expect(
        ex.wholeChordSteps().map((s) => s.ids).toList(),
        [
          {'c0'},
          {'c1'},
          {'c2'},
          {'c3'},
        ],
      );
      expect(ex.chordSteps(2).single.ids, {'c2'});
    });

    testWidgets('PlayingStaffView lights the scheduled ids as time advances',
        (tester) async {
      final pb = ScorePlayback();
      addTearDown(pb.dispose);
      final score = kFormExamples['musical_form']!.first.scoreOf();
      final widget = MaterialApp(
        home: Scaffold(body: PlayingStaffView(score: score, controller: pb)),
      );
      await tester.pumpWidget(widget);
      StaffView staff() => tester.widget<StaffView>(find.byType(StaffView));
      expect(staff().highlightedIds, isEmpty);

      pb.play([
        (ids: {'n0'}, ms: 100),
        (ids: {'n1'}, ms: 100),
      ]);
      await tester.pump(); // controller change → ticker starts
      await tester.pump(const Duration(milliseconds: 20));
      expect(staff().highlightedIds, {'n0'});
      await tester.pump(const Duration(milliseconds: 100));
      expect(staff().highlightedIds, {'n1'});
      await tester.pump(const Duration(milliseconds: 100));
      expect(staff().highlightedIds, isEmpty); // finished → cleared
    });
  });

  testWidgets('the analysis screen renders each example and is tappable',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(FormAnalysisScreen(examples: kFormExamples['musical_form']!)),
    );
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    // Both worked examples and the play-whole control show.
    expect(find.text(l10n.formExampleTernary), findsOneWidget);
    expect(find.text(l10n.formExampleRondo), findsOneWidget);
    expect(find.text(l10n.formAnalysisPlayWhole), findsWidgets);
    expect(find.byType(FormTimeline), findsNWidgets(2));

    // Tapping a section block and the play-whole button don't throw.
    await tester.tap(find.text(l10n.formAnalysisPlayWhole).first);
    await tester.pump();
    await tester.tap(find.byType(FormTimeline).first);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the harmony screen shows function-coloured chords + legend',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(HarmonyAnalysisScreen(examples: kHarmonyExamples['cadences']!)),
    );
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.harmonyExamplePerfect), findsOneWidget);
    expect(find.text(l10n.harmonyExampleHalf), findsOneWidget);
    // The function legend names all three jobs across the two examples.
    expect(find.text(l10n.funcTonic), findsWidgets);
    expect(find.text(l10n.funcDominant), findsWidgets);
    // The cadence markers show under the final chord of each example.
    expect(find.text(l10n.cadenceMarkPerfect), findsOneWidget);
    expect(find.text(l10n.cadenceMarkHalf), findsOneWidget);
    // Chord blocks are tappable without throwing.
    await tester.tap(find.text('V').first);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the analysis hub shows both the form and harmony sections',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(const AnalysisHubScreen()));
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.analysisHubForm.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.analysisHubHarmony.toUpperCase()), findsOneWidget);
    // Both view types are present.
    expect(find.byType(FormAnalysisView), findsWidgets);
    expect(find.byType(HarmonyAnalysisView), findsWidgets);
  });

  group('per-concept prose', () {
    test('every concept in the map now has prose (en + de)', () async {
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      final de = await AppLocalizations.delegate.load(const Locale('de'));
      for (final c in kConcepts) {
        expect(
          conceptProse(en, c.id),
          isNotNull,
          reason: 'missing EN prose for ${c.id}',
        );
        expect(
          conceptProse(de, c.id),
          isNotNull,
          reason: 'missing DE prose for ${c.id}',
        );
      }
      // An id with no concept still falls back to null.
      expect(conceptProse(en, 'not_a_concept'), isNull);
    });

    test('prose is localised (de differs from en)', () async {
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      final de = await AppLocalizations.delegate.load(const Locale('de'));
      expect(
        conceptProse(en, 'intervals'),
        isNot(conceptProse(de, 'intervals')),
      );
      expect(conceptProse(de, 'intervals'), contains('Intervall'));
    });
  });
}
