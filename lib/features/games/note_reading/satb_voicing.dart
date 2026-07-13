// lib/features/games/note_reading/satb_voicing.dart
//
// Shared voicing + rendering for the SATB reading games (Read the Voice, Which
// Voice?, and the ear variant). A random diatonic triad in C major is voiced
// into 2 (Soprano + Alto) or 4 (SATB) parts and laid out on a one- or two-staff
// system, using partitura's `Measure.voice2` (two voices per staff, stems
// up/down) — no voice crossing, Soprano/Alto on treble, Tenor/Bass on bass.

import 'dart:math';

import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:partitura/partitura.dart';

const _whole = NoteDuration(DurationBase.whole);

enum SatbVoice { soprano, alto, tenor, bass }

extension SatbVoiceX on SatbVoice {
  /// Element id used for highlighting.
  String get id => switch (this) {
        SatbVoice.soprano => 's',
        SatbVoice.alto => 'a',
        SatbVoice.tenor => 't',
        SatbVoice.bass => 'b',
      };

  /// Staff the voice is drawn on (S/A treble, T/B bass).
  Clef get clef => this == SatbVoice.tenor || this == SatbVoice.bass
      ? Clef.bass
      : Clef.treble;

  /// Localized display name (the enum's own `.name` stays 'soprano' etc. for ids).
  String label(AppLocalizations l) => switch (this) {
        SatbVoice.soprano => l.voiceSoprano,
        SatbVoice.alto => l.voiceAlto,
        SatbVoice.tenor => l.voiceTenor,
        SatbVoice.bass => l.voiceBass,
      };
}

/// One voice of the current chord: its role and the pitch it sings.
class SatbPart {
  final SatbVoice voice;
  final Pitch pitch;
  const SatbPart(this.voice, this.pitch);
  String get id => voice.id;
}

// Major-key diatonic triads by degree (C major): (root Step, quality). The
// first three are the primary triads (used at the 2-voice level).
const _degrees = <(Step, ChordQuality)>[
  (Step.c, ChordQuality.major), // I
  (Step.f, ChordQuality.major), // IV
  (Step.g, ChordQuality.major), // V
  (Step.d, ChordQuality.minor), // ii
  (Step.e, ChordQuality.minor), // iii
  (Step.a, ChordQuality.minor), // vi
  (Step.b, ChordQuality.diminished), // vii°
];

int _nextTone(int floor, Set<int> pcs) {
  var m = floor;
  while (!pcs.contains(m % 12)) {
    m++;
  }
  return m;
}

// Pitch class → natural Step (C major only, so natural spellings are correct).
const _naturalSteps = <int, Step>{
  0: Step.c,
  2: Step.d,
  4: Step.e,
  5: Step.f,
  7: Step.g,
  9: Step.a,
  11: Step.b,
};

Pitch _pitch(int midi) =>
    Pitch(_naturalSteps[midi % 12]!, octave: midi ~/ 12 - 1);

/// Voice a random C-major diatonic triad into 2 (Soprano + Alto) or, when
/// [satb], 4 parts. Bass sits in octave 3 and each upper voice is the next
/// chord tone above, with Alto pushed to middle C so S/A land on the treble
/// staff and T/B on the bass staff — guaranteeing no voice crossing.
List<SatbPart> voiceRandomChord(Random random, {required bool satb}) {
  final (root, quality) = _degrees[random.nextInt(satb ? 7 : 3)];
  final pcs =
      Triad(Pitch(root), quality).pitches.map((p) => p.midiNumber % 12).toSet();
  final rootPc = Pitch(root).midiNumber % 12;
  final bass = 48 + rootPc;
  final tenor = _nextTone(bass + 3, pcs);
  final alto = _nextTone(max(60, tenor + 1), pcs);
  final soprano = _nextTone(alto + 3, pcs);
  return [
    SatbPart(SatbVoice.soprano, _pitch(soprano)),
    SatbPart(SatbVoice.alto, _pitch(alto)),
    if (satb) SatbPart(SatbVoice.tenor, _pitch(tenor)),
    if (satb) SatbPart(SatbVoice.bass, _pitch(bass)),
  ];
}

Score _staff(Clef clef, SatbPart upper, SatbPart? lower) => Score(
      clef: clef,
      measures: [
        Measure(
          [NoteElement.note(upper.pitch, _whole, id: upper.id)],
          voice2: lower == null
              ? const []
              : [NoteElement.note(lower.pitch, _whole, id: lower.id)],
        ),
      ],
    );

/// The one- (2-voice) or two-staff (SATB) system for [parts].
StaffSystem satbSystem(List<SatbPart> parts) {
  SatbPart of(SatbVoice v) => parts.firstWhere((p) => p.voice == v);
  SatbPart? maybe(SatbVoice v) {
    for (final p in parts) {
      if (p.voice == v) return p;
    }
    return null;
  }

  final hasLower = maybe(SatbVoice.tenor) != null;
  return StaffSystem([
    _staff(Clef.treble, of(SatbVoice.soprano), maybe(SatbVoice.alto)),
    if (hasLower) _staff(Clef.bass, of(SatbVoice.tenor), maybe(SatbVoice.bass)),
  ]);
}
