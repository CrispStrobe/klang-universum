// lib/core/audio/crisp_dsp/formant_shift.dart
//
// Formant shifter — pure-Dart port of crispaudio's dsp/FormantShifter.ts (MIT,
// ours). A simplified time-domain spectral-envelope shift: Hann-windowed frames
// are reindexed by a ratio (scaling the spectral envelope) and overlap-added.
// Despite the upstream file's name it uses NO FFT — it's a direct index scaling,
// which is enough for a convincing perceptual formant shift. The only upstream
// Web-Audio dependency was OfflineAudioContext as a buffer allocator.
//
// Formant shifting changes vocal-tract character (bright "small head" ↔ dark
// "big head") WITHOUT changing pitch or length — ideal for chipmunk/monster
// voice effects on a sample that stays usable as an in-tune tracker instrument.

import 'dart:math';
import 'dart:typed_data';

Float64List _hannWindow(int size) {
  final w = Float64List(size);
  for (var i = 0; i < size; i++) {
    w[i] = 0.5 * (1 - cos((2 * pi * i) / (size - 1)));
  }
  return w;
}

/// Shifts the formants of [input] by [shift] (−1..+1; 0 = no change). Positive
/// shifts formants up (brighter/smaller), negative down (darker/bigger). Pitch
/// and length are preserved. [fftSize] is the analysis frame size.
Float64List formantShift(
  Float64List input,
  double shift, {
  int fftSize = 2048,
}) {
  if (shift == 0 || input.isEmpty) return input;

  final ratio = pow(2, shift).toDouble(); // −1→0.5, +1→2.0
  final hopSize = fftSize ~/ 4;
  final inputLength = input.length;
  final window = _hannWindow(fftSize);
  final output = Float64List(inputLength);

  final frameCount = (inputLength / hopSize).floor();
  for (var frame = 0; frame < frameCount; frame++) {
    final inputPos = frame * hopSize;

    // Extract a windowed frame.
    final frameData = Float64List(fftSize);
    for (var i = 0; i < fftSize; i++) {
      final idx = inputPos + i;
      if (idx < inputLength) frameData[i] = input[idx] * window[i];
    }

    // Reindex by ratio to scale the spectral envelope, overlap-add.
    for (var i = 0; i < fftSize; i++) {
      final scaled = (i * ratio).floor();
      final v = scaled < fftSize ? frameData[scaled] : 0.0;
      final outIdx = inputPos + i;
      if (outIdx < inputLength) output[outIdx] += v;
    }
  }
  return output;
}
