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
