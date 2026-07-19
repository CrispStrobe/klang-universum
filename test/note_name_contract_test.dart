// noteName — the note-naming contract behind dozens of reading games. Only
// "B is H" was spot-checked; these lock the whole map: every step names in
// every style, the German H-system renames only B, solfège is fixed-do, and the
// language-following "auto" path agrees with the explicit English / German-H
// maps for en / de.

import 'package:comet_beat/core/note_naming.dart';
import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart' show Step;
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final de = lookupAppLocalizations(const Locale('de'));

  test('every step names non-empty in every explicit style', () {
    for (final step in Step.values) {
      for (final naming in const [
        NoteNaming.english,
        NoteNaming.germanH,
        NoteNaming.solfege,
      ]) {
        expect(
          noteName(en, step, naming: naming),
          isNotEmpty,
          reason: '$step / $naming',
        );
      }
    }
  });

  test('the German H-system renames ONLY B (natural) to H', () {
    expect(noteName(en, Step.b, naming: NoteNaming.germanH), 'H');
    expect(noteName(en, Step.b, naming: NoteNaming.english), 'B');
    for (final step in Step.values.where((s) => s != Step.b)) {
      expect(
        noteName(en, step, naming: NoteNaming.germanH),
        noteName(en, step, naming: NoteNaming.english),
        reason: 'only B should differ, but $step did',
      );
    }
  });

  test('solfège is the fixed-do syllables', () {
    const expected = {
      Step.c: 'Do',
      Step.d: 'Re',
      Step.e: 'Mi',
      Step.f: 'Fa',
      Step.g: 'Sol',
      Step.a: 'La',
      Step.b: 'Si',
    };
    expected.forEach((step, syllable) {
      expect(noteName(en, step, naming: NoteNaming.solfege), syllable);
    });
  });

  test('the auto path follows the language: en == English, de == German-H', () {
    for (final step in Step.values) {
      expect(
        noteName(en, step),
        noteName(en, step, naming: NoteNaming.english),
        reason: 'en auto should equal English for $step',
      );
      expect(
        noteName(de, step),
        noteName(en, step, naming: NoteNaming.germanH),
        reason: 'de auto should equal German-H for $step',
      );
    }
  });
}
