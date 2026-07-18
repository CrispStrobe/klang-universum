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
import 'package:comet_beat/core/audio/synth.dart'
    show Drum, Segment, midiToFrequency, renderSegmentsRaw;
import 'package:comet_beat/core/audio/tracker_song.dart' show TrackerSong;
import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show
        MultiPartScore,
        MusicElement,
        NoteDuration,
        NoteElement,
        RestElement,
        Score;

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

// --- Score rendering (Song Book / Workshop / TAB all engrave to a Score) -----

int _durMs(NoteDuration d, int quarterMs) {
  final (num, den) = d.fraction; // as a fraction of a whole note
  return (4 * quarterMs * num / den).round();
}

/// A single voice (a flat element list) → PCM: notes become chord segments,
/// rests become silence, so the timing is faithful (unlike the reading games'
/// `playbackOf`, which drops rests + chord tones).
Float64List _renderVoice(List<MusicElement> elements, int quarterMs) {
  final segs = <Segment>[
    for (final e in elements)
      if (e is NoteElement)
        (
          freqs: [for (final p in e.pitches) midiToFrequency(p.midiNumber)],
          ms: _durMs(e.duration, quarterMs),
        )
      else if (e is RestElement)
        (freqs: const <double>[], ms: _durMs(e.duration, quarterMs)),
  ];
  return renderSegmentsRaw(segs);
}

Float64List _sum(List<Float64List> voices) {
  final len = voices.fold<int>(0, (m, v) => v.length > m ? v.length : m);
  final out = Float64List(len);
  for (final v in voices) {
    for (var i = 0; i < v.length; i++) {
      out[i] += v[i];
    }
  }
  return out;
}

/// Render a [Score] to mono PCM at [quarterMs] per quarter note: every voice
/// (1–4) is rendered and summed.
Float64List renderScore(Score score, {int quarterMs = 500}) {
  final voices = <List<MusicElement>>[[], [], [], []];
  for (final m in score.measures) {
    voices[0].addAll(m.elements);
    voices[1].addAll(m.voice2);
    voices[2].addAll(m.voice3);
    voices[3].addAll(m.voice4);
  }
  return _sum([
    for (final v in voices)
      if (v.isNotEmpty) _renderVoice(v, quarterMs),
  ]);
}

/// Render a [MultiPartScore] to mono PCM: every part summed.
Float64List renderMultiPartScore(MultiPartScore mp, {int quarterMs = 500}) =>
    _sum(
      [for (final part in mp.parts) renderScore(part, quarterMs: quarterMs)],
    );

String _scoreCacheKey(MultiPartScore mp, int quarterMs) {
  final b = StringBuffer('score@$quarterMs;');
  for (final part in mp.parts) {
    for (final m in part.measures) {
      for (final voice in [m.elements, m.voice2, m.voice3, m.voice4]) {
        for (final e in voice) {
          if (e is NoteElement) {
            final (n, d) = e.duration.fraction;
            b.write('n${e.pitches.map((p) => p.midiNumber).join(',')}:$n/$d;');
          } else if (e is RestElement) {
            final (n, d) = e.duration.fraction;
            b.write('r$n/$d;');
          }
        }
      }
    }
  }
  return b.toString();
}

/// Any engraved music — a Song Book song, a Workshop document, a TAB score — as
/// a clip source. Renders faithfully (chords + rests + all voices/parts) via the
/// synth. Pass an explicit [key] (e.g. a song id + version) for a cheap cache
/// identity; otherwise a structural key is derived from the notes.
class ScoreSource implements ClipSource {
  ScoreSource(this.score, {this.quarterMs = 500, Object? key}) : _key = key;

  /// Wrap a single-part [score] as a source.
  factory ScoreSource.single(Score score, {int quarterMs = 500, Object? key}) =>
      ScoreSource(MultiPartScore([score]), quarterMs: quarterMs, key: key);

  final MultiPartScore score;
  final int quarterMs;
  final Object? _key;

  // A getter so an edit to [score] invalidates the timeline cache (vector, not
  // bitmap); an explicit [_key] short-circuits the structural walk.
  @override
  Object get cacheKey => _key ?? _scoreCacheKey(score, quarterMs);

  @override
  Float64List render(int sampleRate) =>
      renderMultiPartScore(score, quarterMs: quarterMs);
}

// --- Tracker song -----------------------------------------------------------

/// Structural cache identity for a [TrackerSong]: timing + order + instrument
/// ids + the LIVE current-pattern cells ([TrackerEngine.exportCells], what
/// `renderSongWav` syncs in) + every pattern's cells (all value-hashed). NB two
/// DIFFERENT recorded samples sharing one instrument id would collide — pass an
/// explicit key (a change counter) if a song's instrument SAMPLES are edited in
/// place.
String trackerCacheKey(TrackerSong s) {
  final b =
      StringBuffer('trk@${s.timing.tempoBpm}r${s.rows};o${s.order.join(',')};');
  for (final inst in s.instruments) {
    b.write('i${inst.id};');
  }
  for (final chan in s.engine.exportCells()) {
    for (final c in chan) {
      b.write('${c.hashCode},');
    }
  }
  b.write('#');
  for (final p in s.patterns) {
    for (final chan in p.cells) {
      for (final c in chan) {
        b.write('${c.hashCode},');
      }
    }
    b.write('|');
  }
  return b.toString();
}

/// A Tracker song ([TrackerSong]) as a clip source: rendered offline by its own
/// `renderSongWav` and decoded to mono PCM. [cacheKey] defaults to a structural
/// hash (see [trackerCacheKey]); pass an explicit [key] for a song whose
/// instrument samples change in place.
class TrackerSource implements ClipSource {
  TrackerSource(this.song, {Object? key}) : _key = key;

  final TrackerSong song;
  final Object? _key;

  // A getter so a live edit to [song] invalidates the timeline cache.
  @override
  Object get cacheKey => _key ?? trackerCacheKey(song);

  @override
  Float64List render(int sampleRate) =>
      wavToMonoFloat(readWavPcm16(song.renderSongWav()));
}
