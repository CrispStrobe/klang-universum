// The note-naming convention decouples how note letters are spelled from the
// UI language: a German-UI child can drill English or solfège names, and vice
// versa. `auto` keeps today's behaviour (follow the app language).

import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/note_naming.dart';
import 'package:klang_universum/features/games/note_reading/note_names.dart';
import 'package:klang_universum/l10n/app_localizations_de.dart';
import 'package:klang_universum/l10n/app_localizations_en.dart';
import 'package:partitura/partitura.dart' show Step;

void main() {
  final en = AppLocalizationsEn();
  final de = AppLocalizationsDe();

  test('auto follows the UI language for the natural B', () {
    expect(noteName(en, Step.b), 'B');
    expect(noteName(de, Step.b), 'H');
  });

  test('an explicit convention overrides the UI language', () {
    // German UI, English naming -> B, not H.
    expect(noteName(de, Step.b, naming: NoteNaming.english), 'B');
    // English UI, German naming -> H.
    expect(noteName(en, Step.b, naming: NoteNaming.germanH), 'H');
  });

  test('solfège spells the whole scale', () {
    String s(Step step) => noteName(en, step, naming: NoteNaming.solfege);
    expect(
      [Step.c, Step.d, Step.e, Step.f, Step.g, Step.a, Step.b].map(s).toList(),
      ['Do', 'Re', 'Mi', 'Fa', 'Sol', 'La', 'Si'],
    );
  });

  test('the non-B letters are identical across letter conventions', () {
    for (final step in [Step.c, Step.d, Step.e, Step.f, Step.g, Step.a]) {
      final letter = noteName(en, step, naming: NoteNaming.english);
      expect(noteName(en, step, naming: NoteNaming.germanH), letter);
    }
  });
}
