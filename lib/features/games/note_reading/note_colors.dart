// lib/features/games/note_reading/note_colors.dart
//
// Boomwhacker-style fixed colour per pitch class — the pre-reader colour
// scaffold (toggled in Settings). One stable colour per letter so the same
// note is always the same colour across the reading games; saturated enough to
// read as a notehead fill and, softened, to tint an answer button.

import 'package:flutter/widgets.dart';
import 'package:partitura/partitura.dart';

const Map<Step, Color> kPitchClassColors = {
  Step.c: Color(0xFFE53935), // red
  Step.d: Color(0xFFFB8C00), // orange
  Step.e: Color(0xFFF9A825), // amber (darkened so it reads on white)
  Step.f: Color(0xFF43A047), // green
  Step.g: Color(0xFF00ACC1), // cyan
  Step.a: Color(0xFF3949AB), // indigo
  Step.b: Color(0xFF8E24AA), // purple
};

/// The scaffold colour for [step]'s pitch class.
Color pitchClassColor(Step step) => kPitchClassColors[step]!;
