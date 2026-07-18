// Spot the Parallels — the voice-leading game. The pure half verifies that the
// authored template pool is CORRECTLY labelled by the library (checkVoiceLeading
// is the answer key, so a mislabelled template would ship a wrong answer), that
// the parallel ones are parallel-*only* (crisp), and that transposition keeps the
// label. The widget half drives one round via the grand-staff UI.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/harmony/spot_parallels_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool _hasParallels(List<VoiceLeadingIssue> issues) => issues.any(
      (i) =>
          i.rule == VoiceLeadingRule.parallelFifths ||
          i.rule == VoiceLeadingRule.parallelOctaves,
    );

List<VoiceLeadingIssue> _check(List<int> c1, List<int> c2) =>
    checkVoiceLeading([
      [for (final m in c1) Pitch.fromMidi(m)],
      [for (final m in c2) Pitch.fromMidi(m)],
    ]);

void main() {
  group('template pool is correctly labelled (library = ground truth)', () {
    test('every template.hasParallels matches checkVoiceLeading', () {
      for (final t in kParallelsTemplates) {
        final issues = _check(t.chord1, t.chord2);
        expect(
          _hasParallels(issues),
          t.hasParallels,
          reason: 'template ${t.id} is mislabelled',
        );
      }
    });

    test('clean templates have NO issues at all', () {
      for (final t in kParallelsTemplates.where((t) => !t.hasParallels)) {
        expect(
          _check(t.chord1, t.chord2),
          isEmpty,
          reason: '${t.id} should be spotless',
        );
      }
    });

    test('parallel templates are parallel-ONLY (crisp — no crossing/spacing)',
        () {
      for (final t in kParallelsTemplates.where((t) => t.hasParallels)) {
        final issues = _check(t.chord1, t.chord2);
        expect(issues, isNotEmpty);
        expect(
          issues.every(
            (i) =>
                i.rule == VoiceLeadingRule.parallelFifths ||
                i.rule == VoiceLeadingRule.parallelOctaves,
          ),
          isTrue,
          reason: '${t.id} should only flag parallels',
        );
      }
    });

    test('the pool has both clean and parallel patterns', () {
      expect(kParallelsTemplates.any((t) => t.hasParallels), isTrue);
      expect(kParallelsTemplates.any((t) => !t.hasParallels), isTrue);
    });
  });

  test('transposition preserves the clean/parallel label', () {
    for (final t in kParallelsTemplates) {
      for (final offset in const [2, 5, 7, -3, -5]) {
        final round = buildRound(t, offset);
        final issues = checkVoiceLeading([round.chord1, round.chord2]);
        expect(
          _hasParallels(issues),
          t.hasParallels,
          reason: 'template ${t.id} changed label at offset $offset',
        );
      }
    }
  });

  testWidgets('renders the grand staff + two answer buttons and records SRI',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final sri = SriService(getNow: () => DateTime(2026, 7, 18));

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
          home: SpotParallelsScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GrandStaffView), findsOneWidget);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.spotParallelsClean), findsOneWidget);
    expect(find.text(l10n.spotParallelsParallel), findsOneWidget);

    // Answering records one SRI response under the harmony.parallels namespace.
    await tester.tap(find.text(l10n.spotParallelsClean));
    await tester.pump();
    expect(sri.totalTrackedItems, 1);
    expect(sri.getDetailedBreakdown()['harmony']!.keys, ['parallels']);
    await tester.pumpAndSettle();
  });
}
