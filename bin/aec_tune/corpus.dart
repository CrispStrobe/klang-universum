// bin/aec_tune/corpus.dart
//
// A synthetic AEC evaluation corpus with GROUND TRUTH — the thing an automatic
// tuner scores against. Each scenario is a converge-then-double-talk take: a
// reference (what the "speaker" plays) echoed through a room into a mic, with a
// near-end instrument note added for the second half. Because we synthesize both
// halves we KNOW the true near-end exactly, so SI-SDR and note-survival are both
// computable — the two metrics the tuner maximizes.
//
// This is CLI-only tooling (like bin/aecmos/), kept out of lib/ so it never
// ships in the app. It is deliberately PARAMETRIC, not measured-RIR: the room is
// a decaying random FIR with a chosen delay/length/decay, which gives cheap
// diversity across many rooms. The honest upgrade is to convolve MEASURED room
// impulse responses (OpenSLR-28 / Aachen AIR — redistributable) with real CC0
// cello and the app's own renderLoop() grooves; the scoring code below is
// agnostic to where mic/ref/near come from, so that swap is drop-in.
//
// No Random-in-workflow constraints here (this is a normal CLI), but every
// scenario is SEEDED so a tuning run is reproducible.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show midiToFrequency;

/// One evaluation take with known ground truth.
class AecScenario {
  AecScenario({
    required this.ref,
    required this.mic,
    required this.trueNear,
    required this.doubleTalkFrom,
    required this.nearMidi,
    required this.label,
  });

  /// What the speaker played (the AEC far-end/reference).
  final Float64List ref;

  /// What the mic captured: room-echo of [ref], plus [trueNear] from
  /// [doubleTalkFrom] on.
  final Float64List mic;

  /// The near-end the user actually made — known because we synthesized it.
  /// Zero before [doubleTalkFrom].
  final Float64List trueNear;

  /// Sample index where the near-end joins (the filter converges before this).
  final int doubleTalkFrom;

  /// The MIDI note of the near-end instrument — for note-survival scoring.
  final int nearMidi;

  /// Human-readable description of the room/signal for reports.
  final String label;
}

/// A decaying random-FIR "room": [taps] samples starting at [delay], amplitude
/// decaying at [decay] per tap. Seeded for reproducibility. Real rooms are
/// sparser and longer, but this spans the axis that matters to the filter —
/// delay, tail length, and decay rate.
Float64List _roomIr(
  Random rng, {
  required int delay,
  required int taps,
  required double decay,
}) {
  final ir = Float64List(delay + taps);
  var amp = 1.0;
  for (var i = 0; i < taps; i++) {
    ir[delay + i] = amp * (rng.nextDouble() * 2 - 1);
    amp *= decay;
  }
  return ir;
}

Float64List _convolve(Float64List x, Float64List ir) {
  final out = Float64List(x.length);
  for (var t = 0; t < x.length; t++) {
    var acc = 0.0;
    final jMax = min(ir.length, t + 1);
    for (var j = 0; j < jMax; j++) {
      acc += ir[j] * x[t - j];
    }
    out[t] = acc;
  }
  return out;
}

/// Seeded broadband reference (white noise) — the well-conditioned far-end an
/// adaptive filter converges on, and a stand-in for music/speech energy.
Float64List _noiseRef(Random rng, int n, {double amp = 0.3}) {
  final r = Float64List(n);
  for (var i = 0; i < n; i++) {
    r[i] = amp * (rng.nextDouble() * 2 - 1);
  }
  return r;
}

/// A sustained instrument-like tone (a few harmonics) at [midi] — the near-end
/// whose survival we score.
Float64List _instrument(int midi, int n, int rate, {double amp = 0.3}) {
  final f = midiToFrequency(midi);
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    final t = i / rate;
    out[i] = amp *
        (0.7 * sin(2 * pi * f * t) +
            0.2 * sin(2 * pi * 2 * f * t) +
            0.1 * sin(2 * pi * 3 * f * t));
  }
  return out;
}

/// Build a diverse corpus: [rooms] room variants × the near-end notes in
/// [nearMidis], each a 2-second converge-then-double-talk take. Fully seeded by
/// [seed] so a tuning run is reproducible.
List<AecScenario> buildCorpus({
  int seed = 20260717,
  int rate = 44100,
  double seconds = 2.0,
  int rooms = 4,
  List<int> nearMidis = const [57, 69, 45], // A3 (cello), A4, A2 (low cello)
}) {
  final rng = Random(seed);
  final n = (rate * seconds).round();
  final half = n ~/ 2;
  final out = <AecScenario>[];

  // A spread of rooms along (delay, taps, decay).
  final roomSpecs = <({int delay, int taps, double decay})>[
    (delay: 40, taps: 24, decay: 0.75),
    (delay: 120, taps: 48, decay: 0.85),
    (delay: 240, taps: 96, decay: 0.90),
    (delay: 500, taps: 160, decay: 0.93),
  ];

  for (var ri = 0; ri < rooms; ri++) {
    final spec = roomSpecs[ri % roomSpecs.length];
    final ir =
        _roomIr(rng, delay: spec.delay, taps: spec.taps, decay: spec.decay);
    final ref = _noiseRef(rng, n);
    final echo = _convolve(ref, ir);
    for (final midi in nearMidis) {
      final near = _instrument(midi, n, rate);
      final trueNear = Float64List(n);
      final mic = Float64List(n);
      for (var i = 0; i < n; i++) {
        trueNear[i] = i >= half ? near[i] : 0.0;
        mic[i] = echo[i] + trueNear[i];
      }
      out.add(
        AecScenario(
          ref: ref,
          mic: mic,
          trueNear: trueNear,
          doubleTalkFrom: half,
          nearMidi: midi,
          label: 'room${ri}_d${spec.delay}_t${spec.taps} near=$midi',
        ),
      );
    }
  }
  return out;
}
