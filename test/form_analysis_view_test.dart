// The AnaVis-style form-analysis view: worked form examples shown as a coloured,
// tappable section timeline you can play. Also covers the textbook's per-concept
// prose lookup (conceptProse).
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/games/composition/form_analysis_view.dart';
import 'package:comet_beat/features/games/composition/form_timeline.dart';
import 'package:comet_beat/features/textbook/textbook_i18n.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
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

  group('per-concept prose', () {
    test('authored concepts return prose; others return null', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      // An authored concept has prose; an unauthored one falls back to null.
      expect(conceptProse(l10n, 'intervals'), isNotNull);
      expect(conceptProse(l10n, 'musical_form'), isNotNull);
      expect(conceptProse(l10n, 'pulse'), isNull);
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
