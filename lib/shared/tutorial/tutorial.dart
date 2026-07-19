// lib/shared/tutorial/tutorial.dart
//
// The data model for a minigame's "how to play + what you need to know"
// tutorial. A [Tutorial] is a short deck of [TutorialStep]s; each step is a bit
// of plain-language explanation, optionally paired with a **notated example** (a
// crisp_notation Score rendered on a StaffView) and/or a **playable audio example**
// (a callback onto AudioService). Together they let a child with zero music
// knowledge see it, hear it, then play the game.
//
// Tutorials are built per game, localized, from a factory —
// `Tutorial Function(AppLocalizations)` — so the text follows the app language.
// See tutorial_sheet.dart for how it's shown and tutorial_button.dart for the
// "?" entry point + first-run gating. Rendering-only: no BuildContext here, so
// tutorials stay easy to unit-test.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:crisp_notation/crisp_notation.dart' show Score;
import 'package:flutter/foundation.dart';

/// One option in a step's [TutorialStep.choices] "try it" practice.
@immutable
class TutorialChoice {
  const TutorialChoice(this.label, {this.correct = false});

  /// The button text (already localized).
  final String label;

  /// Whether tapping this option is the right answer.
  final bool correct;
}

/// One page of a tutorial.
@immutable
class TutorialStep {
  const TutorialStep({
    required this.text,
    this.score,
    this.play,
    this.beats,
    this.playLabel,
    this.choices,
  }) : assert(
          choices == null || choices.length >= 2,
          'a "try it" step needs at least two choices (one of them correct)',
        );

  /// The explanation shown on this step (already localized).
  final String text;

  /// Optional engraved example, drawn on a StaffView.
  final Score? score;

  /// Optional "listen" example — given the app's [AudioService], play the sound
  /// this step is teaching (a note, a chord, a little melody). When null, no
  /// listen button is shown. For a melodic line whose notes should **light up
  /// as they play**, prefer [beats] instead.
  final void Function(AudioService audio)? play;

  /// Optional timed monophonic line as `(midi, ms)` steps. When set, the sheet
  /// both plays it (`playSequence`) AND lights the [score]'s notes in time — it
  /// maps the i-th beat to the score element with id `n{i}` (the id scheme the
  /// primer's note helper uses). Takes the place of [play] for a melody.
  final List<(int, int)>? beats;

  /// Label for the listen button (already localized); defaults handled by the
  /// sheet when null.
  final String? playLabel;

  /// Optional "try it" practice: a small set of tap options (labels already
  /// localized, one or more marked `correct`). The sheet renders them as
  /// buttons and gives gentle ✓/✗ feedback — active recall of the fact this
  /// step teaches, with no score and no gate (the child can always continue).
  /// [text] doubles as the question.
  final List<TutorialChoice>? choices;

  bool get hasAudio => play != null || beats != null;

  bool get hasChoices => choices != null && choices!.isNotEmpty;
}

/// A game's tutorial: a titled deck of steps.
@immutable
class Tutorial {
  const Tutorial({required this.title, required this.steps})
      : assert(steps.length > 0, 'a tutorial needs at least one step');

  /// Heading shown at the top of the sheet (already localized).
  final String title;

  final List<TutorialStep> steps;
}
