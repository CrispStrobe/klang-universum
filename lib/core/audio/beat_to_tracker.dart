// Builds a polyphonic drum [TrackerSong] from a shared beat: one percussion
// channel per active drum, so kick + hat on the same step just live on two
// channels (a tracker channel is monophonic per step). Used by the Advanced
// Tracker's "Load shared beat" — it can carry the full beat losslessly, unlike
// the Beginner Tracker's single 3-voice drum channel.
//
// Pure Dart → unit-tested in test/beat_to_tracker_test.dart.

import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show PercussionInstrument, TrackerCell, TrackerChannel, TrackerTiming;
import 'package:comet_beat/core/audio/tracker_song.dart'
    show TrackerPattern, TrackerSong;
import 'package:comet_beat/core/services/beat_bridge.dart' show SharedBeat;

/// A one-pattern drum song: a percussion channel for every drum the [beat]
/// plays, each cell carrying that drum. [stepsPerBeat] defaults to 2 (the shared
/// eighth grid). An empty beat still yields a valid single (kick) channel.
TrackerSong drumSongFromBeat(SharedBeat beat, {int stepsPerBeat = 2}) {
  final steps = beat.steps == 0 ? 16 : beat.steps;
  final fitted = beat.rowsFitted(steps);
  final active = [
    for (final d in Drum.values)
      if (fitted[d]!.contains(true)) d,
  ];
  final drums = active.isEmpty ? const [Drum.kick] : active;

  final channels = [
    for (final d in drums)
      TrackerChannel(
        id: 'drum_${d.name}',
        instrument: PercussionInstrument('drum_${d.name}'),
        rows: steps,
      ),
  ];
  // Channel-major cells: channel c (drum drums[c]) hits on its own steps.
  final cells = <List<TrackerCell>>[
    for (final d in drums)
      [
        for (var s = 0; s < steps; s++)
          fitted[d]![s]
              ? TrackerCell(midi: d.index, volume: 1)
              : TrackerCell.empty,
      ],
  ];

  return TrackerSong.fromParts(
    channels: channels,
    timing: TrackerTiming(
      rows: steps,
      stepsPerBeat: stepsPerBeat,
      tempoBpm: beat.tempoBpm.clamp(32, 255),
    ),
    patterns: [TrackerPattern(name: '00', cells: cells)],
    order: const [0],
  );
}
