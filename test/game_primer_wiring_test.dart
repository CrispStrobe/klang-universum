// The six recently-added games (connect degrees/time/keysig/roadmap, and the
// dynamics/tempo ordering games) should each carry their OWN concept primer,
// not just fall back to the generic module intro. Locks that wiring + checks
// the newly-authored roadmap primer resolves in both locales.

import 'package:comet_beat/features/games/game_registry.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/tutorial/primers.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final byId = {
    for (final g in kGamesByModule.values.expand((x) => x)) g.id: g,
  };

  test('each recently-added / corrected game carries its own primer', () {
    for (final id in const [
      // My six new games.
      'connect_degrees',
      'connect_time',
      'connect_keysig',
      'connect_roadmap',
      'dynamics_order',
      'tempo_order',
      // Corrected: were falling back to a general/mismatched module primer.
      'meter_detective', // march/waltz → strong-beat pattern
      'place_note_bass', // bass reading (not the treble fallback)
      'key_name', // key-signature naming (not the module general)
    ]) {
      expect(byId[id], isNotNull, reason: '$id is registered');
      expect(
        byId[id]!.tutorial,
        isNotNull,
        reason: '$id should have its own concept primer, not the fallback',
      );
    }
  });

  test('roadmapPrimer resolves with non-empty steps in en and de', () {
    for (final locale in const [Locale('en'), Locale('de')]) {
      final tutorial = roadmapPrimer(lookupAppLocalizations(locale));
      expect(tutorial.title, isNotEmpty, reason: locale.languageCode);
      expect(tutorial.steps, isNotEmpty, reason: locale.languageCode);
      for (final step in tutorial.steps) {
        expect(step.text, isNotEmpty, reason: '${locale.languageCode} step');
      }
    }
  });
}
