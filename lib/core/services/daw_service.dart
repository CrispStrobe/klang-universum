// lib/core/services/daw_service.dart
//
// The shared Multitrack (DAW) arrangement. Any module adds clips to it via
// "Send to DAW"; the Multitrack screen displays + bakes it. App-wide (a
// Provider), so a clip sent from the DrumKit or Song Book is still there when
// you open the arranger, and successive sends accumulate into one project.

import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:flutter/foundation.dart';

class DawService extends ChangeNotifier {
  /// The arrangement — starts with two empty named lanes.
  final DawTimeline timeline = DawTimeline(
    tracks: [DawTrack(name: 'A'), DawTrack(name: 'B')],
  );

  // Per-source render cache (the "vector" optimisation): an unchanged clip is
  // served from here instead of re-rendering on every bake.
  final Map<Object, Float64List> _cache = {};

  // Where the next sent clip lands, so successive sends lay out along the
  // timeline rather than stacking at 0.
  double _nextStartMs = 0;

  /// Total clips across all tracks.
  int get clipCount => timeline.tracks.fold(0, (n, t) => n + t.clips.length);

  /// Append a clip from a module to [track] (auto-creating tracks up to it), at
  /// the next free slot. Modules send a SNAPSHOT source (a copy of their model),
  /// so further edits in the module don't retroactively change the sent clip.
  void addClip(ClipSource source, {int track = 0}) {
    while (timeline.tracks.length <= track) {
      timeline.tracks.add(DawTrack(name: '${timeline.tracks.length + 1}'));
    }
    timeline.tracks[track].clips
        .add(Clip(source: source, startMs: _nextStartMs));
    _nextStartMs += 2000;
    notifyListeners();
  }

  /// Mute / unmute a whole track.
  void toggleTrackMute(int track) {
    timeline.tracks[track].muted = !timeline.tracks[track].muted;
    notifyListeners();
  }

  /// Remove one clip.
  void removeClip(int track, int index) {
    timeline.tracks[track].clips.removeAt(index);
    notifyListeners();
  }

  /// Whether a clip is already a baked audio take (a [SampleSource]) rather than
  /// a live "vector" source that re-renders on edit.
  bool isClipFrozen(int track, int index) =>
      timeline.tracks[track].clips[index].source is SampleSource;

  /// **Convert** (freeze) a live clip to a fixed audio take: bake its current
  /// render and replace the vector source with a [SampleSource] of it. The clip
  /// keeps its place/gain/mute but stops tracking edits in its source module and
  /// needs no re-render. One of the maintainer's verbs — a mutable take made
  /// permanent. No-op if already frozen or silent.
  void freezeClip(int track, int index) {
    final clip = timeline.tracks[track].clips[index];
    if (clip.source is SampleSource) return;
    final pcm = _cache.putIfAbsent(
      clip.source.cacheKey,
      () => clip.source.render(kDawSampleRate),
    );
    if (pcm.isEmpty) return;
    timeline.tracks[track].clips[index] = Clip(
      source: SampleSource(pcm),
      startMs: clip.startMs,
      gain: clip.gain,
      muted: clip.muted,
    );
    notifyListeners();
  }

  /// **Merge** clips into one baked audio take, preserving their relative
  /// timing: the group renders (unlimited, so the master limiter still applies
  /// once at final bake) to a single [SampleSource] placed at the earliest
  /// start. Returns null and changes nothing if the group is silent.
  Clip? _mergeGroup(List<Clip> clips) {
    final live = clips.where((c) => !c.muted).toList();
    if (live.isEmpty) return null;
    var minStart = double.infinity;
    for (final c in live) {
      if (c.startMs < minStart) minStart = c.startMs;
    }
    final shifted = [
      for (final c in live) c.copyWith(startMs: c.startMs - minStart),
    ];
    final pcm = renderTimeline(
      DawTimeline(tracks: [DawTrack(clips: shifted)]),
      cache: _cache,
      limit: false,
    );
    if (pcm.isEmpty) return null;
    return Clip(source: SampleSource(pcm), startMs: minStart);
  }

  /// Merge one track's clips into a single audio take on that track.
  void mergeTrack(int track) {
    final merged = _mergeGroup(timeline.tracks[track].clips);
    timeline.tracks[track].clips
      ..clear()
      ..addAll([if (merged != null) merged]);
    notifyListeners();
  }

  /// Merge **every** clip across all tracks into one audio take on track 0
  /// (\"one or many, including all\"). Other lanes are left empty.
  void mergeAll() {
    final all = [for (final t in timeline.tracks) ...t.clips];
    final merged = _mergeGroup(all);
    for (final t in timeline.tracks) {
      t.clips.clear();
    }
    if (merged != null) timeline.tracks[0].clips.add(merged);
    notifyListeners();
  }

  /// Drop every clip (and the render cache).
  void clear() {
    for (final t in timeline.tracks) {
      t.clips.clear();
    }
    _nextStartMs = 0;
    _cache.clear();
    notifyListeners();
  }

  /// Bake the whole arrangement to one mono PCM buffer (only changed clips
  /// re-render, thanks to the per-source cache).
  Float64List bake() => renderTimeline(timeline, cache: _cache);
}
