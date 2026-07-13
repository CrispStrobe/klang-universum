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

/// A single-measure staff of [midis] as notes of the given [dur], on [clef]
/// (treble by default; pass `Clef.bass` for low-voice/cello/drum examples).
Score _notes(
  List<int> midis, {
  DurationBase dur = DurationBase.quarter,
  Clef clef = Clef.treble,
}) =>
    Score(
      clef: clef,
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

/// Chords have jobs: home (Tonic), pull (Dominant), the journey (cadence).
/// Module: harmony.
Tutorial harmonyPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerHarmonyTitle,
      steps: [
        TutorialStep(
          text: l10n.primerHarmonyHome,
          score: _chord([60, 64, 67]), // C major = home (Tonic)
          play: (a) => a.playMidiChord([60, 64, 67]),
        ),
        TutorialStep(
          text: l10n.primerHarmonyPull,
          score: _chord([67, 71, 74]), // G major = Dominant, pulls home
          play: (a) => a.playChordSequence([
            [67, 71, 74], // Dominant leaning...
            [60, 64, 67], // ...back to home
          ]),
        ),
        TutorialStep(
          text: l10n.primerHarmonyCadence,
          play: (a) => a.playChordSequence([
            [60, 64, 67], // I  — home
            [65, 69, 72], // IV — away
            [67, 71, 74], // V  — pull
            [60, 64, 67], // I  — home again
          ]),
        ),
      ],
    );

/// A melody is a journey; phrases ask a question and give an answer.
/// Module: composition.
Tutorial compositionPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerCompositionTitle,
      steps: [
        TutorialStep(
          text: l10n.primerCompositionJourney,
          score: _notes([60, 62, 64, 65, 64, 62, 60]), // up then home
          play: (a) => a.playSequence(_run([60, 62, 64, 65, 64, 62, 60])),
        ),
        TutorialStep(
          text: l10n.primerCompositionQuestion,
          score: _notes([60, 62, 64, 67]), // stops up on G — unfinished
          play: (a) => a.playSequence(_run([60, 62, 64, 67])),
        ),
        TutorialStep(
          text: l10n.primerCompositionAnswer,
          score: _notes([67, 65, 64, 62, 60]), // comes home to C
          play: (a) => a.playSequence(_run([67, 65, 64, 62, 60])),
        ),
      ],
    );

/// The four cello strings (C G D A) on the bass clef, and how fingers raise
/// the pitch. Module: cello.
Tutorial celloPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerCelloTitle,
      steps: [
        TutorialStep(
          text: l10n.primerCelloStrings,
          score: _notes([36, 43, 50, 57], clef: Clef.bass), // C G D A
          play: (a) => a.playSequence(_run([36, 43, 50, 57], ms: 600)),
        ),
        TutorialStep(
          text: l10n.primerCelloBass,
          score: _notes([36], clef: Clef.bass), // low C, thickest string
          play: (a) => a.playMidiNote(36),
        ),
        TutorialStep(
          text: l10n.primerCelloFinger,
          score: _notes([43, 45, 47], clef: Clef.bass), // G, then higher
          play: (a) => a.playSequence(_run([43, 45, 47], ms: 500)),
        ),
      ],
    );

/// The six guitar strings (E A D G B E) and how tab works. Module: guitar.
Tutorial guitarPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerGuitarTitle,
      steps: [
        TutorialStep(
          // Written an octave up, as guitar notation is — E3..E5.
          text: l10n.primerGuitarStrings,
          score: _notes([52, 57, 62, 67, 71, 76]), // E A D G B E
          play: (a) => a.playSequence(_run([52, 57, 62, 67, 71, 76], ms: 450)),
        ),
        TutorialStep(
          text: l10n.primerGuitarTab,
          play: (a) => a.playMidiNote(52), // the open low-E string
        ),
        TutorialStep(
          text: l10n.primerGuitarPlay,
          score: _notes([52, 76]), // low E up to high E
          play: (a) => a.playSequence(_run([52, 76], ms: 700)),
        ),
      ],
    );

/// How the song screens work: a tune drawn left-to-right, a marker to follow.
/// Module: songs.
Tutorial songsPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerSongsTitle,
      steps: [
        TutorialStep(
          text: l10n.primerSongsPick,
          score: _notes([60, 60, 67, 67, 69, 69, 67]), // Twinkle, line 1
          play: (a) => a.playSequence(_run([60, 60, 67, 67, 69, 69, 67])),
        ),
        TutorialStep(
          text: l10n.primerSongsMarker,
          score: _notes([65, 65, 64, 64, 62, 62, 60]), // Twinkle, line 2
          play: (a) => a.playSequence(_run([65, 65, 64, 64, 62, 62, 60])),
        ),
      ],
    );

/// The piano layout (white A–G, black in 2s and 3s), finding C, the grand
/// staff. Module: keyboard.
Tutorial keyboardPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerKeyboardTitle,
      steps: [
        TutorialStep(
          text: l10n.primerKeyboardWhite,
          play: (a) => a.playSequence(_run(_cMajor)),
        ),
        TutorialStep(
          text: l10n.primerKeyboardFindC,
          score: _notes(_cMajor),
          play: (a) => a.playSequence(_run(_cMajor)),
        ),
        TutorialStep(
          text: l10n.primerKeyboardHands,
          // Left hand low C + right hand C–E–G, sounding together.
          play: (a) => a.playMidiChord([48, 60, 64, 67]),
        ),
      ],
    );

/// Transposing instruments read one note and sound another. Module: transpose.
Tutorial transposePrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerTransposeTitle,
      steps: [
        TutorialStep(
          text: l10n.primerTransposeSame,
          score: _notes([60]), // read C...
          play: (a) => a.playMidiNote(60), // ...hear C
        ),
        TutorialStep(
          text: l10n.primerTransposeShift,
          score: _notes([60]), // read C on a B-flat instrument...
          play: (a) => a.playSequence(_run([60, 58], ms: 700)), // ...sounds B♭
        ),
      ],
    );

/// Drum notation: which drum + when, not pitch. Module: drums.
Tutorial drumsPrimer(AppLocalizations l10n) => Tutorial(
      title: l10n.primerDrumsTitle,
      steps: [
        TutorialStep(
          text: l10n.primerDrumsWhat,
          play: (a) =>
              a.playSequence([(36, 300), (50, 300), (36, 300), (50, 300)]),
        ),
        TutorialStep(
          text: l10n.primerDrumsLines,
          score: _notes([36, 50, 36, 50], clef: Clef.bass), // kick / snare row
          play: (a) => a.playSequence(_run([36, 50, 36, 50], ms: 360)),
        ),
      ],
    );
