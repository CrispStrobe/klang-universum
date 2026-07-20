// drumSongFromBeat: a shared beat → a polyphonic drum TrackerSong (one
// percussion channel per active drum). Pure Dart, no device audio.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/beat_to_tracker.dart';
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show PercussionInstrument, SampleInstrument;
import 'package:comet_beat/core/audio/tracker_instrument_codec.dart'
    show instrumentToJsonString;
import 'package:comet_beat/core/services/beat_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<bool> row(List<int> hits, {int len = 8}) =>
      [for (var i = 0; i < len; i++) hits.contains(i)];

  test('builds one percussion channel per active drum, polyphony preserved',
      () {
    // kick + hat share step 0 — a tracker channel is monophonic, so they must
    // land on SEPARATE channels.
    final beat = SharedBeat(
      rows: {
        Drum.kick: row([0, 4]),
        Drum.hat: row([0, 2, 4, 6]),
        Drum.snare: row([4]),
      },
      tempoBpm: 120,
    );
    final song = drumSongFromBeat(beat);

    expect(song.channelCount, 3); // kick, hat, snare
    for (final ch in song.channels) {
      expect(ch.instrument, isA<PercussionInstrument>());
    }
    expect(song.rows, 8);
    expect(song.timing.tempoBpm, 120);

    // Each channel carries exactly its own drum on its own steps.
    Map<Drum, List<int>> hitsByDrum() {
      final out = <Drum, List<int>>{};
      for (final ch in song.channels) {
        for (var s = 0; s < song.rows; s++) {
          final midi = ch.cells[s].midi;
          if (midi != null) {
            (out[Drum.values[midi]] ??= []).add(s);
          }
        }
      }
      return out;
    }

    final hits = hitsByDrum();
    expect(hits[Drum.kick], [0, 4]);
    expect(hits[Drum.hat], [0, 2, 4, 6]);
    expect(hits[Drum.snare], [4]);
  });

  test('an empty beat still yields a valid single-channel song', () {
    final song = drumSongFromBeat(SharedBeat(rows: const {}, tempoBpm: 100));
    expect(song.channelCount, 1);
    expect(song.channels.single.instrument, isA<PercussionInstrument>());
    // Renders without throwing (silence is fine).
    expect(song.renderSongWav().length, greaterThan(44));
  });

  test('a per-drum voice override becomes that channel instrument', () {
    final pcm = Float64List.fromList([
      for (var i = 0; i < 200; i++) i % 20 < 10 ? 0.5 : -0.5,
    ]);
    final beat = SharedBeat(
      rows: {
        Drum.kick: row([0, 4]),
      },
      tempoBpm: 120,
      voices: {
        Drum.kick: SharedVoice(
          'Boom',
          instrumentToJsonString(SampleInstrument('boom', pcm)),
        ),
      },
    );
    final song = drumSongFromBeat(beat);

    // The kick channel plays the sample voice, not the synth percussion voice.
    final inst = song.channels.single.instrument;
    expect(inst, isA<SampleInstrument>());
    expect(inst, isNot(isA<PercussionInstrument>()));
    // Its hits play note 60 (the sample's natural pitch), not the drum index.
    for (var s = 0; s < song.rows; s++) {
      final midi = song.channels.single.cells[s].midi;
      if (midi != null) expect(midi, 60);
    }
  });

  test('the built song renders audible drums', () {
    final beat = SharedBeat(
      rows: {
        Drum.kick: row([0, 2, 4, 6]),
      },
      tempoBpm: 120,
    );
    final wav = drumSongFromBeat(beat).renderSongWav();
    expect(wav.length, greaterThan(44));
  });
}
