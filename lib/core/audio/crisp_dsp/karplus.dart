// Karplus-Strong plucked-string synthesis — a tiny physical-model that turns a
// noise burst into a decaying plucked tone (guitar / harp / koto / plucked
// bass). Zero assets, zero license risk (it's an algorithm), and genuinely
// "instrument-like" — the cheapest convincing real-instrument timbre, which is
// why it complements the Tracker's four additive voices. Flutter-free, pure Dart.
//
// The algorithm: fill a delay line of length N ≈ sampleRate/freq with noise,
// then repeatedly read it out while feeding each sample back through a one-pole
// averaging lowpass. The delay length sets the PITCH; the lowpass progressively
// darkens + decays the tone, exactly like a real string losing its high
// partials first.

import 'dart:math';
import 'dart:typed_data';

/// One plucked note at [freq] Hz, [samples] long, at [sampleRate].
///
/// [damping] (0.90–0.999) scales the feedback: lower = shorter/plukkier, higher
/// = longer sustain. [blend] (0..1) mixes the averaging (1 = pure string) toward
/// a sign-flipping "drum" mode (0 = noisy/percussive) — keep near 1 for a
/// string. [seed] makes the noise burst deterministic (stable stem cache). The
/// output is peak-normalized to [amp] with a short attack declick.
Float64List karplusPluck({
  required double freq,
  required int samples,
  int sampleRate = 44100,
  double damping = 0.996,
  double blend = 1.0,
  double amp = 0.9,
  int seed = 0,
}) {
  final out = Float64List(samples <= 0 ? 0 : samples);
  if (out.isEmpty || freq <= 0) return out;

  final n = max(2, (sampleRate / freq).round());
  final buf = Float64List(n);
  final rng = Random(seed);
  for (var i = 0; i < n; i++) {
    buf[i] = rng.nextDouble() * 2 - 1; // white-noise excitation
  }

  final d = damping.clamp(0.80, 0.9999);
  final b = blend.clamp(0.0, 1.0);
  var pos = 0;
  var peak = 0.0;
  for (var i = 0; i < samples; i++) {
    final cur = buf[pos];
    out[i] = cur;
    if (cur.abs() > peak) peak = cur.abs();
    final nxt = buf[(pos + 1) % n];
    // Averaging lowpass (string); the (1-b) term flips sign occasionally for a
    // more percussive/noisy attack when blend < 1.
    final avg = 0.5 * (cur + nxt);
    final sign = (rng.nextDouble() < b) ? 1.0 : -1.0;
    buf[pos] = d * avg * sign;
    pos = (pos + 1) % n;
  }

  // Peak-normalize + a ~3 ms attack declick so the burst onset doesn't click.
  final scale = peak > 0 ? amp / peak : 0.0;
  final attack = min(samples, (0.003 * sampleRate).round());
  for (var i = 0; i < samples; i++) {
    var g = scale;
    if (i < attack) g *= i / attack;
    out[i] *= g;
  }
  return out;
}
