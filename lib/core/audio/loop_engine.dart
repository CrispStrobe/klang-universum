// lib/core/audio/loop_engine.dart
//
// Pure-Dart loop engine behind the Loop Mixer toy: a fixed set of 2-bar track
// patterns (all authored in C pentatonic, so any combination is consonant), an
// enabled set, and a mixdown of the enabled tracks to one seamless-looping WAV
// (offline-mix-then-loop: one player, one buffer → sample-accurate sync).
// Flutter-free, like synth.dart — unit-tested without a device.
//
// Levels are combo-independent by design: each track carries an authored gain
// into mixStems' unit-peak-per-stem + soft-limiter mixdown, so toggling one
// card never changes how loud the others are (per-combo peak normalization
// would pump). Renders are cached per (tempo, enabled-set) so re-toggles are
// instant.

import 'dart:typed_data';

import 'package:klang_universum/core/audio/synth.dart';

/// The musical clock the patterns render against: 2 bars of 4/4 on an
/// eighth-note step grid. Supported tempos keep the step length an integral
/// number of ms (and of samples at 44.1 kHz), so every track's segments sum to
/// exactly the same sample count and the loop seam stays click-free.
class LoopTiming {
  const LoopTiming({required this.tempoBpm});

  final int tempoBpm;

  static const beatsPerBar = 4;
  static const bars = 2;

  /// Steps are eighths: 16 per 2-bar loop.
  static const totalSteps = beatsPerBar * bars * 2;

  int get beatMs => 60000 ~/ tempoBpm;
  int get stepMs => beatMs ~/ 2;
  int get totalMs => stepMs * totalSteps;
  int get totalSamples => (totalMs * kSampleRate) ~/ 1000;
  Duration get loopLength => Duration(milliseconds: totalMs);
}

/// One toggleable loop layer: an id (stable, used by l10n/tests), an authored
/// mix level, and a pattern render onto the shared timing grid.
class LoopTrack {
  const LoopTrack({
    required this.id,
    required this.gain,
    required this.render,
  });

  final String id;
  final double gain;
  final Float64List Function(LoopTiming timing) render;
}

// --- The authored content: everything in C pentatonic (C D E G A) ---

const _c2 = 36, _e2 = 40, _g2 = 43, _a2 = 45;
const _a3 = 57, _c4 = 60, _d4 = 62, _e4 = 64, _g4 = 67, _a4 = 69;
const _g5 = 79, _a5 = 81, _c6 = 84;

/// A melodic step pattern → segments: each entry is `(midi, lengthInSteps)`
/// with `null` midi for a rest. Lengths must sum to [LoopTiming.totalSteps].
Float64List _melodic(
  LoopTiming timing,
  Instrument instrument,
  List<(List<int>?, int)> pattern,
) {
  assert(
    pattern.fold<int>(0, (sum, p) => sum + p.$2) == LoopTiming.totalSteps,
    'pattern must fill the loop exactly',
  );
  final segments = <Segment>[
    for (final (midis, steps) in pattern)
      (
        freqs: [for (final m in midis ?? const <int>[]) midiToFrequency(m)],
        ms: steps * timing.stepMs,
      ),
  ];
  return renderSegmentsRaw(segments, timbre: timbreFor(instrument));
}

Float64List _drums(LoopTiming timing) {
  final s = timing.stepMs;
  return renderDrumPattern(
    [
      // A straight backbeat: kick on 1 & 3, snare on 2 & 4, hats on the
      // eighths — with a pickup kick at the end of bar 2 to lean into the wrap.
      for (var bar = 0; bar < 2; bar++) ...[
        (s * (bar * 8 + 0), Drum.kick),
        (s * (bar * 8 + 2), Drum.snare),
        (s * (bar * 8 + 4), Drum.kick),
        (s * (bar * 8 + 6), Drum.snare),
      ],
      (s * 15, Drum.kick),
      for (var step = 0; step < LoopTiming.totalSteps; step++)
        if (step.isOdd) (s * step, Drum.hat),
    ],
    totalMs: timing.totalMs,
  );
}

/// The Loop Mixer's built-in band. Order = display order on the screen.
final List<LoopTrack> kLoopMixerTracks = [
  const LoopTrack(id: 'drums', gain: 0.50, render: _drums),
  LoopTrack(
    id: 'bass',
    gain: 0.55,
    render: (t) => _melodic(t, Instrument.cello, [
      ([_c2], 2), ([_c2], 2), ([_g2], 2), ([_a2], 2), // bar 1
      ([_e2], 2), ([_g2], 2), ([_a2], 2), ([_g2], 2), // bar 2
    ]),
  ),
  LoopTrack(
    id: 'chords',
    gain: 0.30,
    render: (t) => _melodic(t, Instrument.flute, [
      ([_c4, _e4, _g4], 8), // bar 1: C major pad
      ([_a3, _c4, _e4], 8), // bar 2: A minor pad
    ]),
  ),
  LoopTrack(
    id: 'melody',
    gain: 0.40,
    render: (t) => _melodic(t, Instrument.piano, [
      ([_e4], 1), ([_g4], 1), ([_a4], 1), (null, 1), // bar 1
      ([_g4], 1), ([_e4], 1), ([_d4], 2),
      ([_c4], 1), ([_d4], 1), ([_e4], 1), ([_g4], 1), // bar 2
      ([_a4], 2), ([_g4], 1), ([_e4], 1),
    ]),
  ),
  LoopTrack(
    id: 'sparkle',
    gain: 0.28,
    render: (t) => _melodic(t, Instrument.musicBox, [
      (null, 2), ([_c6], 1), (null, 3), ([_a5], 1), (null, 1), // bar 1
      (null, 2), ([_g5], 1), (null, 3), ([_c6], 1), (null, 1), // bar 2
    ]),
  ),
];

/// Holds the toggle state and renders the current combo to a loopable WAV.
class LoopEngine {
  LoopEngine({List<LoopTrack>? tracks, int tempoBpm = 100})
      : tracks = tracks ?? kLoopMixerTracks,
        _tempoBpm = tempoBpm;

  final List<LoopTrack> tracks;
  final Set<String> enabled = {};

  int _tempoBpm;
  int get tempoBpm => _tempoBpm;
  set tempoBpm(int bpm) {
    if (bpm == _tempoBpm) return;
    _tempoBpm = bpm;
    _wavCache.clear();
    _stemCache.clear();
  }

  LoopTiming get timing => LoopTiming(tempoBpm: _tempoBpm);

  // Rendered stems per track id (at the current tempo) and mixed WAVs per
  // enabled-set — synthesis is the expensive part, so a re-toggle is instant.
  final Map<String, Float64List> _stemCache = {};
  final Map<String, Uint8List> _wavCache = {};

  /// Toggles [id]; returns true if the track is now enabled.
  bool toggle(String id) {
    assert(tracks.any((t) => t.id == id), 'unknown track "$id"');
    if (!enabled.remove(id)) {
      enabled.add(id);
      return true;
    }
    return false;
  }

  /// The current combo as one loop-ready WAV (an empty set renders silence of
  /// the full loop length).
  Uint8List renderLoop() {
    final key = tracks.map((t) => enabled.contains(t.id) ? '1' : '0').join();
    return _wavCache[key] ??= wavBytes(
      mixStems(
        [
          for (final track in tracks)
            if (enabled.contains(track.id))
              (
                samples: _stemCache[track.id] ??= track.render(timing),
                gain: track.gain,
              ),
        ],
        totalSamples: timing.totalSamples,
      ),
    );
  }
}
