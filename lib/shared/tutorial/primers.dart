// lib/shared/tutorial/primers.dart
//
// Worked example content for the tutorial framework. `readingPrimer` is the
// first fully-authored tutorial: it teaches, from zero, that music sits on a
// staff, that higher-on-the-staff means higher-in-pitch (shown AND played), and
// that every note has a letter name. It exercises every part of the framework —
// localized text, engraved examples, playable audio — and is the template the
// per-module primers (note values, measures, scales, chords, …) will follow.
//
// These will migrate next to their games as content is authored per module
// (tracked in PLAN.md "Learnability & UX"); kept here for now to land the
// framework without touching the hot per-game files.

import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/midi_pitch.dart';
import 'package:klang_universum/shared/tutorial/tutorial.dart';
import 'package:partitura/partitura.dart'
    show Clef, DurationBase, Measure, NoteDuration, NoteElement, Score;

const _quarter = NoteDuration(DurationBase.quarter);

/// A single-measure treble staff of the given MIDI notes (quarter notes).
Score _staff(List<int> midis) => Score(
      clef: Clef.treble,
      measures: [
        Measure([
          for (var i = 0; i < midis.length; i++)
            NoteElement.note(pitchFromMidi(midis[i]), _quarter, id: 'n$i'),
        ]),
      ],
    );

/// The zero-knowledge "reading notes" primer (treble clef).
Tutorial readingPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerReadingTitle,
      steps: [
        // 1. What a staff is.
        TutorialStep(
          text: l10n.primerReadingStaff,
          score: _staff([64, 67, 71]), // E G B
        ),
        // 2. Higher on the staff = higher sound (shown + heard, ascending).
        TutorialStep(
          text: l10n.primerReadingHigher,
          score: _staff([60, 64, 67, 72]), // C E G C'
          play: (audio) => audio.playSequence(
            const [(60, 400), (64, 400), (67, 400), (72, 650)],
          ),
        ),
        // 3. Every note has a letter name — here's one, listen to it.
        TutorialStep(
          text: l10n.primerReadingNames,
          score: _staff([64]), // E
          play: (audio) => audio.playMidiNote(64),
        ),
      ],
    );
