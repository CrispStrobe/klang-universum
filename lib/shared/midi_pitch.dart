// lib/shared/midi_pitch.dart
//
// Spell a MIDI number as a crisp_notation [Pitch]. Instrument input surfaces (piano,
// guitar, cello) produce MIDI numbers; the notation model needs a spelled
// pitch. Naturals stay natural; the five black keys are spelled as sharps —
// the plain choice for a kids' sandbox.

import 'package:crisp_notation/crisp_notation.dart';

const List<(Step, int)> _spelling = [
  (Step.c, 0), // 0  C
  (Step.c, 1), // 1  C#
  (Step.d, 0), // 2  D
  (Step.d, 1), // 3  D#
  (Step.e, 0), // 4  E
  (Step.f, 0), // 5  F
  (Step.f, 1), // 6  F#
  (Step.g, 0), // 7  G
  (Step.g, 1), // 8  G#
  (Step.a, 0), // 9  A
  (Step.a, 1), // 10 A#
  (Step.b, 0), // 11 B
];

/// The [Pitch] for a MIDI note number (60 = C4), spelling accidentals as sharps.
Pitch pitchFromMidi(int midi) {
  final octave = (midi ~/ 12) - 1;
  final (step, alter) = _spelling[midi % 12];
  return Pitch(step, alter: alter, octave: octave);
}
