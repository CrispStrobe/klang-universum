// lib/features/games/note_reading/note_names.dart
//
// Note letter names in the learner's chosen convention. `auto` goes through the
// ARB files (German uses H for the natural B); the explicit conventions use the
// maps below so a German-UI child can still drill English/solfège names.

import 'package:flutter/widgets.dart';
import 'package:klang_universum/core/note_naming.dart';
import 'package:klang_universum/core/services/settings_service.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

const _english = <Step, String>{
  Step.c: 'C',
  Step.d: 'D',
  Step.e: 'E',
  Step.f: 'F',
  Step.g: 'G',
  Step.a: 'A',
  Step.b: 'B',
};
const _germanH = <Step, String>{
  Step.c: 'C',
  Step.d: 'D',
  Step.e: 'E',
  Step.f: 'F',
  Step.g: 'G',
  Step.a: 'A',
  Step.b: 'H',
};
const _solfege = <Step, String>{
  Step.c: 'Do',
  Step.d: 'Re',
  Step.e: 'Mi',
  Step.f: 'Fa',
  Step.g: 'Sol',
  Step.a: 'La',
  Step.b: 'Si',
};

String noteName(
  AppLocalizations l10n,
  Step step, {
  NoteNaming naming = NoteNaming.auto,
}) =>
    switch (naming) {
      NoteNaming.auto => _localized(l10n, step),
      NoteNaming.english => _english[step]!,
      NoteNaming.germanH => _germanH[step]!,
      NoteNaming.solfege => _solfege[step]!,
    };

String _localized(AppLocalizations l10n, Step step) => switch (step) {
      Step.c => l10n.noteNameC,
      Step.d => l10n.noteNameD,
      Step.e => l10n.noteNameE,
      Step.f => l10n.noteNameF,
      Step.g => l10n.noteNameG,
      Step.a => l10n.noteNameA,
      Step.b => l10n.noteNameB,
    };

/// [step] spelled in the learner's chosen convention (from [SettingsService]).
/// Use this from widget builds; falls back to `auto` where the app language wins.
String noteNameFor(BuildContext context, Step step) => noteName(
      AppLocalizations.of(context)!,
      step,
      naming: context.watch<SettingsService>().noteNaming,
    );
