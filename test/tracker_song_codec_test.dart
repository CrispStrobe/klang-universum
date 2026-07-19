// TrackerSong JSON codec: a whole song survives a lossless round-trip and
// renders byte-identically afterwards (the safety net — a dropped field would
// change the decoded render). Uses procedural voices so the render is exact
// (SampleInstrument PCM is Float32-lossy; covered in the instrument codec test).

import 'package:comet_beat/core/audio/crisp_dsp/fm.dart';
import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/audio/tracker_song_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A song exercising every serialized dimension: two channels (gain/pan/mute/
  // envelope/insert-effect), two patterns of DIFFERENT lengths, cells with
  // note/volume/effect/fxCmd/fxParam/per-cell-instrument, an order list that
  // repeats, a non-default timing, and a shared instrument pool.
  TrackerSong richSong({bool muteCh1 = false}) {
    List<TrackerCell> pat0Ch0() {
      final c = List<TrackerCell>.filled(8, TrackerCell.empty);
      c[0] = const TrackerCell(midi: 60, volume: 0.8);
      c[2] = const TrackerCell(midi: 62, effect: TrackerEffect.vibrato);
      c[4] = const TrackerCell(midi: 64, fxCmd: 0x1, fxParam: 0x04); // porta
      c[6] = const TrackerCell(midi: 65, instrument: 2); // per-cell pool voice
      return c;
    }

    List<TrackerCell> pat0Ch1() {
      final c = List<TrackerCell>.filled(8, TrackerCell.empty);
      c[1] = const TrackerCell(midi: 48, volume: 0.5);
      c[5] = const TrackerCell(midi: 50, instrument: 1);
      return c;
    }

    // Pattern 1 is SHORTER (4 rows) — per-pattern variable length.
    List<TrackerCell> pat1(int base) {
      final c = List<TrackerCell>.filled(4, TrackerCell.empty);
      c[0] = TrackerCell(midi: base);
      c[3] = TrackerCell(midi: base + 3, volume: 0.6);
      return c;
    }

    final ch0 = TrackerChannel(
      id: 'lead',
      instrument: const AdditiveInstrument('piano', Instrument.piano),
      rows: 8,
      gain: 0.7,
      pan: -0.5,
      volumeEnvelope: const VolumeEnvelope([
        (ms: 0, level: 0.2),
        (ms: 200, level: 1.0),
        (ms: 600, level: 0.0),
      ]),
    );
    final ch1 = TrackerChannel(
      id: 'bass',
      instrument: const KarplusInstrument('pluck', damping: 0.99, blend: 0.8),
      rows: 8,
      gain: 0.4,
      pan: 0.3,
      panEnvelope: const PanEnvelope([
        (ms: 0, pan: -1.0),
        (ms: 500, pan: 1.0),
      ]),
      effects: [TrackerChannelEffect.delay],
    )..muted = muteCh1;

    return TrackerSong.fromParts(
      channels: [ch0, ch1],
      timing: const TrackerTiming(
        tempoBpm: 100,
        rows: 8,
        stepsPerBeat: 2,
        swing: 0.1,
      ),
      patterns: [
        TrackerPattern(name: 'intro', cells: [pat0Ch0(), pat0Ch1()]),
        TrackerPattern(
          name: 'turn',
          cells: [pat1(55), pat1(43)],
        ),
      ],
      order: [0, 1, 0],
      instruments: [
        const AdditiveInstrument('cello', Instrument.cello), // pool 1
        const FmInstrument('ep', FmPreset(ratio: 1, index: 2)), // pool 2
      ],
    );
  }

  group('trackerSongToJson / fromJson', () {
    test('a rich song round-trips + renders byte-identically', () {
      final song = richSong();
      final decoded = trackerSongFromJsonString(trackerSongToJsonString(song));

      // The safety net: identical render → no serialized field was dropped.
      expect(decoded.renderSongWav(), song.renderSongWav());
    });

    test('structure + metadata survive exactly', () {
      final song = richSong();
      final d = trackerSongFromJson(trackerSongToJson(song));

      expect(d.channels.length, 2);
      expect(d.channels[0].id, 'lead');
      expect(d.channels[0].gain, 0.7);
      expect(d.channels[0].pan, -0.5);
      expect(d.channels[0].volumeEnvelope, isNotNull);
      expect(d.channels[1].id, 'bass');
      expect(d.channels[1].panEnvelope, isNotNull);
      expect(d.channels[1].effects, [TrackerChannelEffect.delay]);

      expect(d.order, [0, 1, 0]);
      expect(d.timing.tempoBpm, 100);
      expect(d.timing.stepsPerBeat, 2);
      expect(d.timing.swing, 0.1);
      expect(d.instruments.length, 2);

      // Per-pattern length preserved (pattern 1 is shorter).
      expect(d.patterns[0].name, 'intro');
      expect(d.patterns[0].cells.first.length, 8);
      expect(d.patterns[1].name, 'turn');
      expect(d.patterns[1].cells.first.length, 4);

      // Every cell field survives.
      final c4 = d.patterns[0].cells[0][4];
      expect(c4.midi, 64);
      expect(c4.fxCmd, 0x1);
      expect(c4.fxParam, 0x04);
      final c2 = d.patterns[0].cells[0][2];
      expect(c2.effect, TrackerEffect.vibrato);
      final c6 = d.patterns[0].cells[0][6];
      expect(c6.instrument, 2);
      final c0 = d.patterns[0].cells[0][0];
      expect(c0.volume, 0.8);
    });

    test('mute survives (a muted channel stays silent)', () {
      final unmuted = richSong();
      final muted =
          trackerSongFromJson(trackerSongToJson(richSong(muteCh1: true)));
      expect(muted.channels[1].muted, isTrue);
      // Muting ch1 changes the mix → the rendered bytes differ in content
      // (isNot(equals) compares element-wise, unlike Uint8List `==`).
      expect(muted.renderSongWav(), isNot(unmuted.renderSongWav()));
    });

    test('the JSON carries the format tag + version', () {
      final json = trackerSongToJson(richSong());
      expect(json['format'], kTrackerSongFormat);
      expect(json['version'], kTrackerSongVersion);
    });

    test('an empty cell serializes as null (compact)', () {
      final song = richSong();
      final json = trackerSongToJson(song);
      final pat0 = (json['patterns'] as List).first as Map<String, dynamic>;
      final ch0Cells = (pat0['cells'] as List).first as List;
      expect(ch0Cells[1], isNull); // an empty step is null, not an object
      expect((ch0Cells[0] as Map)['n'], 60); // a note step carries its data
    });
  });
}
