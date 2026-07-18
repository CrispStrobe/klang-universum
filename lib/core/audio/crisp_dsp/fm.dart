// Two-operator FM synthesis — one carrier phase-modulated by one modulator. A
// tiny, classic engine that covers a whole family of melodic timbres the
// additive voices and sfxr can't: electric piano / Rhodes, bells, tines, metallic
// leads, synth bass. Zero assets, zero license risk (it's math). Flutter-free.
//
// out(t) = amp · env(t) · sin(2π·f·t + I(t)·sin(2π·f·ratio·t))
//
// [ratio] (modulator/carrier freq) sets the harmonic character — integer ratios
// are pitched/tonal, non-integer ratios go bell-like/inharmonic. [index] is the
// modulation depth (brightness); it and the amplitude both decay exponentially
// across the note, so a struck-then-mellowing tone falls out naturally.

import 'dart:math';
import 'dart:typed_data';

/// One FM note at [freq] Hz, [samples] long, at [sampleRate].
///
/// [ratio] = modulator freq ÷ carrier freq. [index] = peak modulation depth,
/// falling to ~0 over the note at rate [indexDecay] (higher = brightness dies
/// faster). [ampDecay] shapes the amplitude decay (higher = plukkier/percussive;
/// ~0 = sustained). Peak-normalized to [amp] with a short attack declick.
Float64List fmVoice({
  required double freq,
  required int samples,
  int sampleRate = 44100,
  double ratio = 1.0,
  double index = 2.0,
  double indexDecay = 3.0,
  double ampDecay = 2.5,
  double amp = 0.9,
}) {
  final out = Float64List(samples <= 0 ? 0 : samples);
  if (out.isEmpty || freq <= 0) return out;

  final dur = samples / sampleRate;
  final wc = 2 * pi * freq / sampleRate; // carrier phase increment
  final wm = 2 * pi * freq * ratio / sampleRate; // modulator phase increment
  final attack = min(samples, (0.003 * sampleRate).round());

  var peak = 0.0;
  for (var i = 0; i < samples; i++) {
    final t = i / sampleRate;
    final decayT = t / dur;
    final ai = index * exp(-indexDecay * decayT); // instantaneous mod index
    final env = exp(-ampDecay * decayT);
    final s = env * sin(wc * i + ai * sin(wm * i));
    out[i] = s;
    if (s.abs() > peak) peak = s.abs();
  }

  final scale = peak > 0 ? amp / peak : 0.0;
  for (var i = 0; i < samples; i++) {
    var g = scale;
    if (i < attack) g *= i / attack;
    out[i] *= g;
  }
  return out;
}

/// A named 2-op FM preset (the ratio/index/decay knobs above), for the sound
/// library. Kept as plain data so [FmInstrument] can be `const`.
class FmPreset {
  const FmPreset({
    required this.ratio,
    required this.index,
    this.indexDecay = 3.0,
    this.ampDecay = 2.5,
  });

  final double ratio;
  final double index;
  final double indexDecay;
  final double ampDecay;
}

/// The built-in FM palette. Electric piano (Rhodes-ish, ratio 1), bell
/// (inharmonic ratio 3.5, slow decay), and a punchy FM bass (sub-ratio 0.5).
const kFmPresets = <String, FmPreset>{
  'ePiano': FmPreset(ratio: 1, index: 2, ampDecay: 2.2),
  'fmBell': FmPreset(ratio: 3.5, index: 4, indexDecay: 1.6, ampDecay: 1.1),
  'fmBass': FmPreset(ratio: 0.5, index: 3, indexDecay: 5, ampDecay: 2.4),
};
