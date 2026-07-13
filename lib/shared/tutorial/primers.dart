// lib/shared/tutorial/primers.dart
//
// Authored tutorial content: one zero-knowledge "primer" per module, teaching
// exactly the musical facts its games drill — each fact shown (engraved
// notation) AND heard (playable audio). These are attached to representative
// games in game_registry.dart via GameInfo.tutorial and auto-shown on first
// play (see features/games/tutorial_gate.dart). Text lives in the ARBs (EN/DE).
//
// Adding a module's primer: write it here, add its ARB strings, and hang it on
// the module's entry game. See PLAN.md "Learnability & UX".

import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/midi_pitch.dart';
import 'package:klang_universum/shared/tutorial/tutorial.dart';
import 'package:partitura/partitura.dart'
    show Clef, DurationBase, Measure, NoteDuration, NoteElement, Score;

// ---- notation helpers -------------------------------------------------------

/// A single-measure treble staff of [midis] as notes of the given [dur].
Score _notes(List<int> midis, {DurationBase dur = DurationBase.quarter}) =>
    Score(
      clef: Clef.treble,
      measures: [
        Measure([
          for (var i = 0; i < midis.length; i++)
            NoteElement.note(
              pitchFromMidi(midis[i]),
              NoteDuration(dur),
              id: 'n$i',
            ),
        ]),
      ],
    );

/// A single stacked chord (whole note) of [midis] on a treble staff.
Score _chord(List<int> midis) => Score(
      clef: Clef.treble,
      measures: [
        Measure([
          NoteElement(
            pitches: midis.map(pitchFromMidi).toList(),
            duration: const NoteDuration(DurationBase.whole),
            id: 'chord',
          ),
        ]),
      ],
    );

const _cMajor = [60, 62, 64, 65, 67, 69, 71, 72]; // C D E F G A B C
const _aMinor = [57, 59, 60, 62, 64, 65, 67, 69]; // A B C D E F G A

List<(int, int)> _run(List<int> midis, {int ms = 320}) =>
    [for (final m in midis) (m, ms)];

// ---- primers ----------------------------------------------------------------

/// Reading notes on the staff (treble). Module: note_reading.
Tutorial readingPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerReadingTitle,
      steps: [
        TutorialStep(
          text: l10n.primerReadingStaff,
          score: _notes([64, 67, 71]), // E G B
        ),
        TutorialStep(
          text: l10n.primerReadingHigher,
          score: _notes([60, 64, 67, 72]), // C E G C'
          play: (a) => a.playSequence(_run([60, 64, 67, 72])),
        ),
        TutorialStep(
          text: l10n.primerReadingNames,
          score: _notes([64]), // E
          play: (a) => a.playMidiNote(64),
        ),
      ],
    );

/// How long a note lasts. Module: note_values.
Tutorial noteValuesPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerValuesTitle,
      steps: [
        TutorialStep(
          text: l10n.primerValuesWhole,
          score: _notes([60], dur: DurationBase.whole),
          play: (a) => a.playNoteLength(4, isRest: false),
        ),
        TutorialStep(
          text: l10n.primerValuesQuarter,
          score: _notes([60, 60, 60, 60]),
          play: (a) => a.playSequence(_run([60, 60, 60, 60], ms: 480)),
        ),
        TutorialStep(
          text: l10n.primerValuesRest,
          play: (a) => a.playNoteLength(1, isRest: true),
        ),
      ],
    );

/// Filling a measure to the beat. Module: measures.
Tutorial measuresPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerMeasuresTitle,
      steps: [
        TutorialStep(text: l10n.primerMeasuresBars),
        TutorialStep(
          text: l10n.primerMeasuresFill,
          score: _notes([60, 62, 64, 65]), // 4 quarters
          play: (a) => a.playSequence(_run([60, 62, 64, 65], ms: 480)),
        ),
        TutorialStep(
          text: l10n.primerMeasuresHalf,
          score: _notes([60, 64], dur: DurationBase.half),
          play: (a) => a.playSequence(_run([60, 64], ms: 960)),
        ),
      ],
    );

/// A scale is a ladder of notes; major vs minor colour. Module: scales.
Tutorial scalesPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerScalesTitle,
      steps: [
        TutorialStep(
          text: l10n.primerScalesLadder,
          score: _notes(_cMajor),
          play: (a) => a.playSequence(_run(_cMajor)),
        ),
        TutorialStep(
          text: l10n.primerScalesMajor,
          play: (a) => a.playSequence(_run(_cMajor)),
        ),
        TutorialStep(
          text: l10n.primerScalesMinor,
          play: (a) => a.playSequence(_run(_aMinor)),
        ),
      ],
    );

/// Stacking notes into chords/triads; major vs minor. Module: chords.
Tutorial chordsPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerChordsTitle,
      steps: [
        TutorialStep(
          text: l10n.primerChordsStack,
          score: _chord([60, 64, 67]), // C E G
          play: (a) => a.playMidiChord([60, 64, 67]),
        ),
        TutorialStep(
          text: l10n.primerChordsColour,
          play: (a) => a.playChordSequence([
            [60, 64, 67], // C major
            [60, 63, 67], // C minor
          ]),
        ),
        TutorialStep(
          text: l10n.primerChordsArpeggio,
          play: (a) => a.playArpeggioThenChord([60, 64, 67]),
        ),
      ],
    );
