// Subtractive synthesis — a raw oscillator (saw / square) shaped by a
// envelope-swept lowpass filter. The classic groovebox/analog-synth voice: pads,
// leads, organs, synth bass — the sustained side of the melodic palette that FM
// and plucked strings don't cover. Zero assets, zero license (it's math).
// Flutter-free, pure Dart.
//
// osc(t) → one-pole lowpass whose cutoff sweeps from [cutoffStart] toward
// [cutoffEnd] over the note (the filter "wah"), then an attack+decay amp
// envelope. A saw is bright/buzzy (strings, brass, bass); a square is
// hollow/woody (leads, organ, clarinet-ish).

import 'dart:math';
import 'dart:typed_data';

/// The raw oscillator shape fed into the filter.
enum SubWave { saw, square }

/// One subtractive note at [freq] Hz, [samples] long, at [sampleRate].
///
/// [cutoffStart]/[cutoffEnd] are 0..1 (mapped to ~50 Hz…8 kHz); the cutoff
/// sweeps between them at rate [cutoffDecay] (higher = snappier filter). [attack]
/// smooths the onset; [ampDecay] shapes the amplitude fade (0 ≈ sustained pad,
/// high ≈ plucky). Peak-normalized to [amp].
Float64List subtractiveVoice({
  required double freq,
  required int samples,
  int sampleRate = 44100,
  SubWave wave = SubWave.saw,
  double cutoffStart = 0.6,
  double cutoffEnd = 0.15,
  double cutoffDecay = 3.0,
  double attack = 0.008,
  double ampDecay = 1.2,
  double amp = 0.9,
}) {
  final out = Float64List(samples <= 0 ? 0 : samples);
  if (out.isEmpty || freq <= 0) return out;

  final dur = samples / sampleRate;
  final phaseInc = freq / sampleRate; // cycles per sample (0..1 ramp)
  final attackN = min(samples, (attack * sampleRate).round());

  var phase = 0.0;
  var lp = 0.0; // one-pole lowpass state
  var peak = 0.0;
  for (var i = 0; i < samples; i++) {
    // Oscillator.
    final raw = wave == SubWave.saw
        ? 2 * phase - 1 // rising saw, −1..+1
        : (phase < 0.5 ? 1.0 : -1.0); // square
    phase += phaseInc;
    if (phase >= 1.0) phase -= 1.0;

    // Envelope-swept one-pole lowpass.
    final decayT = i / sampleRate / dur;
    final cutoff =
        cutoffEnd + (cutoffStart - cutoffEnd) * exp(-cutoffDecay * decayT);
    final fc = 50 + cutoff.clamp(0.0, 1.0) * 7950; // Hz
    final a = 1 - exp(-2 * pi * fc / sampleRate);
    lp += a * (raw - lp);

    // Amp envelope.
    final env = exp(-ampDecay * decayT);
    final s = lp * env;
    out[i] = s;
    if (s.abs() > peak) peak = s.abs();
  }

  final scale = peak > 0 ? amp / peak : 0.0;
  for (var i = 0; i < samples; i++) {
    var g = scale;
    if (i < attackN) g *= i / attackN;
    out[i] *= g;
  }
  return out;
}

/// A named subtractive preset for the sound library. Plain data so
/// [SubtractiveInstrument] can be `const`.
class SubPreset {
  const SubPreset({
    required this.wave,
    this.cutoffStart = 0.6,
    this.cutoffEnd = 0.15,
    this.cutoffDecay = 3.0,
    this.ampDecay = 1.2,
  });

  final SubWave wave;
  final double cutoffStart;
  final double cutoffEnd;
  final double cutoffDecay;
  final double ampDecay;
}

/// The built-in subtractive palette: a slow open pad (saw, gentle decay), a
/// bright square lead, and a punchy saw synth bass.
const kSubPresets = <String, SubPreset>{
  'pad': SubPreset(
    wave: SubWave.saw,
    cutoffStart: 0.5,
    cutoffEnd: 0.25,
    cutoffDecay: 1.5,
    ampDecay: 0.4,
  ),
  'lead': SubPreset(
    wave: SubWave.square,
    cutoffStart: 0.8,
    cutoffEnd: 0.4,
    cutoffDecay: 2.5,
    ampDecay: 1.0,
  ),
  'synthBass': SubPreset(
    wave: SubWave.saw,
    cutoffStart: 0.5,
    cutoffEnd: 0.08,
    cutoffDecay: 4.0,
    ampDecay: 1.6,
  ),
};
