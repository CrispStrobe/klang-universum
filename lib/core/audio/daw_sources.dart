// lib/core/audio/daw_sources.dart
//
// Per-module ClipSource adapters — the "vector clip" layer that lets each
// module's MODEL sit on a DAW track. Each wraps the module's existing OFFLINE
// renderer and derives a cacheKey from the model's value, so the timeline
// re-renders a clip only when its source model actually changes (the whole
// point of the vector, not bitmap, design — see docs/DAW_SCOPING.md).

import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/core/audio/wav_io.dart';

/// A DrumKit beat — a [DrumRowsPattern] played at a [LoopTiming] — as a clip
/// source. Renders directly via the pattern's own offline renderer.
class DrumSource implements ClipSource {
  DrumSource(this.pattern, this.timing);

  final DrumRowsPattern pattern;
  final LoopTiming timing;

  @override
  Float64List render(int sampleRate) => pattern.render(timing);

  @override
  Object get cacheKey => drumCacheKey(pattern, timing);
}

/// Cache identity for a drum beat: the grid rows + the timing that renders them
/// (tempo/swing/bars). Equal key ⇒ identical audio.
String drumCacheKey(DrumRowsPattern p, LoopTiming t) {
  final rows = [
    for (final d in Drum.values)
      (p.rows[d] ?? const <bool>[]).map((b) => b ? '1' : '0').join(),
  ].join('|');
  return 'drum:$rows@${t.tempoBpm}s${t.swing}b${t.bars}';
}

/// A Loop Mixer groove — a [GrooveSpec] — as a clip source. Rendered offline by
/// a fresh [LoopEngine] (the same restore path the KU1 share token uses), then
/// decoded to mono PCM. The spec's canonical [GrooveSpec.cacheKey] is the cache
/// identity.
class GrooveSource implements ClipSource {
  GrooveSource(this.spec);

  final GrooveSpec spec;

  @override
  Float64List render(int sampleRate) {
    final wav = (LoopEngine()..applySpec(spec)).renderLoop();
    return wavToMonoFloat(readWavPcm16(wav));
  }

  @override
  Object get cacheKey => 'groove:${spec.cacheKey}';
}
