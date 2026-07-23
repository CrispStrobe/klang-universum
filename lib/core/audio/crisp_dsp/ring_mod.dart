// lib/core/audio/crisp_dsp/ring_mod.dart
//
// A **ring modulator** for the Tracker channel chain / SFX — multiplies the
// signal by a sine carrier for clangy, metallic, robot-y timbres. Pure Dart,
// deterministic, a SAME-LENGTH transform (`Float64List → Float64List`).
// Flutter-free, tested like sample_dsp_test.dart. See docs/FX_HANDOVER.md #1.
//
// Contract:
//   • `wet[i] = input[i] * sin(2π * carrierHz * i / sampleRate)`; blend
//     `out[i] = (1-mix)*input[i] + mix*wet[i]`. `mix` in [0,1]; **mix == 0 MUST be
//     an exact copy of the input** (identity). Clamp mix to [0,1].
//   • Output length == input length; deterministic (no RNG/clock); finite; bounded
//     (|wet| ≤ |input|). A constant (DC) input becomes a pure carrier tone — the
//     test detects `carrierHz` back out of a DC input via the app's MPM detector.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;

/// Ring-modulates [input] with a [carrierHz] sine. [mix] blends wet/dry.
Float64List ringModFx(
  Float64List input, {
  double carrierHz = 220,
  double mix = 1,
  int sampleRate = kSampleRate,
  double phaseRadians = 0,
}) {
  final m = mix.clamp(0.0, 1.0);
  final out = Float64List(input.length);
  // mix == 0 is an exact element-wise copy of the input (identity).
  if (m == 0.0) {
    out.setRange(0, input.length, input);
    return out;
  }
  final w = 2 * math.pi * carrierHz / sampleRate;
  for (var i = 0; i < input.length; i++) {
    final dry = input[i];
    final wet = dry * math.sin(w * i + phaseRadians);
    out[i] = (1 - m) * dry + m * wet;
  }
  return out;
}
