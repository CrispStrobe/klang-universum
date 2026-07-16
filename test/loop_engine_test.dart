// LoopEngine — the Loop Mixer's Flutter-free core. Covers the timing grid,
// the mixdown invariants (silence, no clipping, combo-independent levels) and
// the render cache. Mirrors synth_test.dart: pure Dart, no device audio.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/audio/loop_engine.dart';
import 'package:klang_universum/core/audio/synth.dart';

Int16List _pcm(Uint8List wav) => Int16List.sublistView(wav, 44);

int _peak(Uint8List wav) {
  final data = ByteData.sublistView(wav);
  var peak = 0;
  for (var i = 44; i + 1 < wav.length; i += 2) {
    final s = data.getInt16(i, Endian.little).abs();
    if (s > peak) peak = s;
  }
  return peak;
}

void main() {
  test('supported tempos keep the step grid integral in ms and samples', () {
    for (final bpm in [75, 100, 120]) {
      final t = LoopTiming(tempoBpm: bpm);
      expect(t.beatMs * bpm, 60000, reason: '$bpm bpm beat is integral');
      expect(t.stepMs * 2, t.beatMs, reason: '$bpm bpm step is integral');
      expect(
        (t.stepMs * kSampleRate) % 1000,
        0,
        reason: '$bpm bpm step is a whole sample count',
      );
      expect(t.totalMs, t.stepMs * LoopTiming.totalSteps);
    }
  });

  test('built-in tracks: unique ids, and every stem fills the loop', () {
    final ids = kLoopMixerTracks.map((t) => t.id).toList();
    expect(ids.toSet().length, ids.length);

    const timing = LoopTiming(tempoBpm: 100);
    for (final track in kLoopMixerTracks) {
      final stem = track.render(timing);
      expect(
        stem.length,
        timing.totalSamples,
        reason: '${track.id} stem length',
      );
      expect(
        stem.any((v) => v.abs() > 1e-6),
        isTrue,
        reason: '${track.id} renders audio',
      );
    }
  });

  test('empty set renders full-length silence', () {
    final engine = LoopEngine();
    final wav = engine.renderLoop();
    expect(wav.length, 44 + engine.timing.totalSamples * 2);
    expect(_peak(wav), 0);
  });

  test('toggling tracks changes the render; the mix never clips', () {
    final engine = LoopEngine();
    expect(engine.toggle('drums'), isTrue);
    final drums = engine.renderLoop();
    expect(_peak(drums), greaterThan(2000), reason: 'audible');

    expect(engine.toggle('bass'), isTrue);
    final drumsBass = engine.renderLoop();
    expect(drumsBass, isNot(equals(drums)));

    for (final track in engine.tracks) {
      engine.enabled.add(track.id);
    }
    final full = engine.renderLoop();
    // The tanh soft-knee caps the sum below full scale even with all tracks.
    expect(_peak(full), lessThan(32767));
    expect(engine.toggle('drums'), isFalse, reason: 'toggle off');
  });

  test('a track sounds the same alone as inside a mix (no level pumping)', () {
    final engine = LoopEngine();
    engine.enabled.add('chords');
    final solo = _pcm(engine.renderLoop());

    engine.enabled.add('sparkle');
    final mixed = _pcm(engine.renderLoop());

    // The sparkle pattern is silent for its first two steps, so there the mix
    // must be (near-)identical to the solo chord render — a per-combo
    // normalization would rescale it. tanh compression differs only at high
    // amplitude, so allow a small tolerance.
    final quiet = (engine.timing.stepMs * kSampleRate) ~/ 1000;
    for (var i = 0; i < quiet; i++) {
      expect((mixed[i] - solo[i]).abs(), lessThanOrEqualTo(64), reason: '@$i');
    }
  });

  test('renders are cached per combo and invalidated by tempo', () {
    final engine = LoopEngine();
    engine.enabled.add('melody');
    final first = engine.renderLoop();
    expect(identical(first, engine.renderLoop()), isTrue, reason: 'cache hit');

    engine.tempoBpm = 120;
    final faster = engine.renderLoop();
    expect(identical(first, faster), isFalse);
    expect(faster.length, lessThan(first.length), reason: 'shorter loop');
  });

  test('mixStems places drum hits without clipping and pads short stems', () {
    final hit = renderDrumPattern([(0, Drum.kick)], totalMs: 100);
    final mixed = mixStems(
      [(samples: hit, gain: 1.0), (samples: hit, gain: 1.0)],
      totalSamples: 8820, // 200 ms — longer than the stems
    );
    expect(mixed.length, 8820);
    var peak = 0;
    for (final s in mixed) {
      if (s.abs() > peak) peak = s.abs();
    }
    expect(peak, greaterThan(10000));
    expect(peak, lessThan(32767));
    // The padded tail stays silent.
    expect(mixed.sublist(5000).any((s) => s != 0), isFalse);
  });
}
