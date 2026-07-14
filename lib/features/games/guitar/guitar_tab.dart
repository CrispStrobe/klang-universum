// lib/features/games/guitar/guitar_tab.dart
//
// Guitar first-position map for the Gitarren-Ecke (instrument corner), the
// same recipe as the Cello-Ecke but on tablature (crisp_notation v0.8 TabStaffView
// + Tuning). Standard tuning, top tab line = string 1 (high E4), bottom line =
// string 6 (low E2). Only naturals in the open position (frets 0–4).
//
// Each entry's (stringIndex, fret) is the lowest-fret assignment the tab layout
// engine renders (Tuning.fretFor) — asserted in guitar_tab_test.dart — so what
// the child sees on the staff always matches this table.

import 'package:crisp_notation/crisp_notation.dart';

/// Standard six-string tuning; top tab line first (E4 B3 G3 D3 A2 E2).
final Tuning kGuitarTuning = Tuning.standardGuitar;

/// A first-position note: [stringIndex] (0 = top line / string 1 / high E),
/// [fret] (0 = open), and the sounding [pitch].
class GuitarNote {
  final int stringIndex;
  final int fret;
  final Pitch pitch;

  const GuitarNote(this.stringIndex, this.fret, this.pitch);

  /// Conventional string number: string 1 = high E (top line), 6 = low E.
  int get stringNumber => stringIndex + 1;

  bool get isOpen => fret == 0;
}

/// The six open strings, string 1 (high E) first.
const kGuitarOpenStrings = <GuitarNote>[
  GuitarNote(0, 0, Pitch(Step.e)), // string 1
  GuitarNote(1, 0, Pitch(Step.b, octave: 3)), // string 2
  GuitarNote(2, 0, Pitch(Step.g, octave: 3)), // string 3
  GuitarNote(3, 0, Pitch(Step.d, octave: 3)), // string 4
  GuitarNote(4, 0, Pitch(Step.a, octave: 2)), // string 5
  GuitarNote(5, 0, Pitch(Step.e, octave: 2)), // string 6
];

/// Open-position naturals across all six strings (frets 0–4). Every entry is
/// its own lowest-fret position, so it renders exactly here on the tab.
const kGuitarFirstPosition = <GuitarNote>[
  // String 6 (low E2)
  GuitarNote(5, 0, Pitch(Step.e, octave: 2)),
  GuitarNote(5, 1, Pitch(Step.f, octave: 2)),
  GuitarNote(5, 3, Pitch(Step.g, octave: 2)),
  // String 5 (A2)
  GuitarNote(4, 0, Pitch(Step.a, octave: 2)),
  GuitarNote(4, 2, Pitch(Step.b, octave: 2)),
  GuitarNote(4, 3, Pitch(Step.c, octave: 3)),
  // String 4 (D3)
  GuitarNote(3, 0, Pitch(Step.d, octave: 3)),
  GuitarNote(3, 2, Pitch(Step.e, octave: 3)),
  GuitarNote(3, 3, Pitch(Step.f, octave: 3)),
  // String 3 (G3)
  GuitarNote(2, 0, Pitch(Step.g, octave: 3)),
  GuitarNote(2, 2, Pitch(Step.a, octave: 3)),
  // String 2 (B3)
  GuitarNote(1, 0, Pitch(Step.b, octave: 3)),
  GuitarNote(1, 1, Pitch(Step.c)),
  GuitarNote(1, 3, Pitch(Step.d)),
  // String 1 (high E4)
  GuitarNote(0, 0, Pitch(Step.e)),
  GuitarNote(0, 1, Pitch(Step.f)),
  GuitarNote(0, 3, Pitch(Step.g)),
];

/// The fretted (non-open) notes — the material for the tab-reading game.
final List<GuitarNote> kGuitarFrettedNotes =
    kGuitarFirstPosition.where((n) => !n.isOpen).toList();
