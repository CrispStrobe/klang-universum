// lib/features/games/composition/daw_screen.dart
//
// The Multitrack — the DAW Workshop tool (docs/DAW_SCOPING.md). Clips from any
// module sit on tracks in time; Play BAKES the whole arrangement offline
// (renderTimeline, per-source cache) and plays it. A "vector, not bitmap"
// arranger: each clip references its source MODEL and renders on demand.
//
// This first surface seeds demo clips (a beat + a tune) so the arranger is
// usable before the per-module "Send to DAW" bridges land. Per-track mute + a
// clip strip; drag-in-time and pixel-accurate widths are polish follow-ups.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_sources.dart';
import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/audio/loop_engine.dart'
    show DrumRowsPattern, LoopTiming, kPatternSteps;
import 'package:comet_beat/core/audio/synth.dart' show Drum, wavBytes;
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show
        Clef,
        DurationBase,
        Measure,
        NoteDuration,
        NoteElement,
        Pitch,
        Score,
        Step;
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

/// Test handle onto the running arranger.
@visibleForTesting
abstract interface class DawTester {
  int get trackCount;
  int get clipCount;
  bool get isPlaying;
  bool isTrackMuted(int track);
  void toggleTrackMute(int track);
  void addDemoBeat();
  void addDemoTune();
  void clear();
  void play();
  void stop();

  /// Test seam: the length (samples) the arrangement bakes to.
  int debugBakeLength();
}

class DawScreen extends StatefulWidget {
  const DawScreen({super.key});

  @override
  State<DawScreen> createState() => _DawScreenState();
}

class _DawScreenState extends State<DawScreen> implements DawTester {
  // Two named lanes to start with.
  final DawTimeline _timeline = DawTimeline(
    tracks: [DawTrack(name: 'A'), DawTrack(name: 'B')],
  );
  final Map<Object, Float64List> _cache = {};
  bool _playing = false;

  // Where the next added clip lands, so demo clips lay out along the timeline.
  double _nextStartMs = 0;

  AudioService get _audio => context.read<AudioService>();

  // --- DawTester -------------------------------------------------------------

  @override
  int get trackCount => _timeline.tracks.length;

  @override
  int get clipCount => _timeline.tracks.fold(0, (n, t) => n + t.clips.length);

  @override
  bool get isPlaying => _playing;

  @override
  bool isTrackMuted(int track) => _timeline.tracks[track].muted;

  @override
  void toggleTrackMute(int track) {
    setState(
      () => _timeline.tracks[track].muted = !_timeline.tracks[track].muted,
    );
    if (_playing) play(); // re-bake with the change
  }

  DrumRowsPattern _demoBeat() {
    final rows = {
      for (final d in Drum.values) d: List<bool>.filled(kPatternSteps, false),
    };
    for (var s = 0; s < kPatternSteps; s += 4) {
      rows[Drum.kick]![s] = true;
    }
    for (var s = 2; s < kPatternSteps; s += 4) {
      rows[Drum.snare]![s] = true;
    }
    for (var s = 0; s < kPatternSteps; s += 2) {
      rows[Drum.hat]![s] = true;
    }
    return DrumRowsPattern(rows);
  }

  Score _demoTune() {
    const q = NoteDuration(DurationBase.quarter);
    return Score(
      clef: Clef.treble,
      measures: [
        Measure([
          NoteElement.note(const Pitch(Step.c), q),
          NoteElement.note(const Pitch(Step.e), q),
          NoteElement.note(const Pitch(Step.g), q),
          NoteElement.note(const Pitch(Step.c, octave: 5), q),
        ]),
      ],
    );
  }

  @override
  void addDemoBeat() {
    setState(() {
      _timeline.tracks[0].clips.add(
        Clip(
          source: DrumSource(_demoBeat(), const LoopTiming(tempoBpm: 100)),
          startMs: _nextStartMs,
        ),
      );
      _nextStartMs += 2000;
    });
  }

  @override
  void addDemoTune() {
    setState(() {
      _timeline.tracks[1].clips.add(
        Clip(
          source: ScoreSource.single(_demoTune()),
          startMs: _nextStartMs,
        ),
      );
      _nextStartMs += 2000;
    });
  }

  @override
  void clear() {
    setState(() {
      for (final t in _timeline.tracks) {
        t.clips.clear();
      }
      _nextStartMs = 0;
    });
    _cache.clear();
  }

  Float64List _bake() => renderTimeline(_timeline, cache: _cache);

  Int16List _toPcm16(Float64List pcm) {
    final out = Int16List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      out[i] = (pcm[i].clamp(-1.0, 1.0) * 32767).round();
    }
    return out;
  }

  @override
  int debugBakeLength() => _bake().length;

  @override
  void play() {
    final pcm = _bake();
    if (pcm.isEmpty) return;
    if (!_audio.soundOn) return;
    _audio.playWavBytes(wavBytes(_toPcm16(pcm)));
    setState(() => _playing = true);
  }

  @override
  void stop() {
    _audio.stop();
    setState(() => _playing = false);
  }

  // --- UI --------------------------------------------------------------------

  String _clipLabel(Clip clip) {
    final s = clip.source;
    final kind = s is DrumSource
        ? '🥁'
        : s is ScoreSource
            ? '🎼'
            : s is GrooveSource
                ? '🎛️'
                : s is TrackerSource
                    ? '🎹'
                    : '🎵';
    return '$kind ${(clip.startMs / 1000).toStringAsFixed(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: GameAppBar(
        title: l10n.dawTitle,
        actions: [
          IconButton(
            icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
            tooltip: _playing ? l10n.songStop : l10n.myMelodyPlay,
            onPressed: _playing ? stop : play,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.trackerClear,
            onPressed: clipCount == 0 ? null : clear,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: clipCount == 0
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l10n.dawEmpty,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        for (var i = 0; i < _timeline.tracks.length; i++)
                          _trackRow(i, scheme),
                      ],
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: addDemoBeat,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.dawAddBeat),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: addDemoTune,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.dawAddTune),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trackRow(int i, ColorScheme scheme) {
    final track = _timeline.tracks[i];
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Text(
                track.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: Icon(track.muted ? Icons.volume_off : Icons.volume_up),
              color: track.muted ? scheme.error : null,
              onPressed: () => toggleTrackMute(i),
            ),
            Expanded(
              child: SizedBox(
                height: 40,
                child: track.clips.isEmpty
                    ? null
                    : ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final clip in track.clips)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2),
                              child: Chip(label: Text(_clipLabel(clip))),
                            ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
