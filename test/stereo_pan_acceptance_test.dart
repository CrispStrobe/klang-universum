// ACCEPTANCE GATE for Feature C — stereo output + panning.
// Owned by the orchestrator (opus tracker-replayer). DO NOT EDIT.
// Implement the contract in docs/TRACKER_ENGINE_CONTRACTS.md until this passes.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:flutter_test/flutter_test.dart';

int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
int _u32(Uint8List b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

void main() {
  group('Feature C — stereo + panning', () {
    test('regression: a no-pan song renders a MONO WAV', () {
      final s = TrackerSong(timing: const TrackerTiming(rows: 4));
      s.engine.setCell(0, 0, const TrackerCell(midi: 60));
      s.syncCurrent();
      expect(s.usesPan, isFalse);
      final wav = s.renderCurrentPatternWav();
      expect(_u16(wav, 22), 1); // numChannels == 1 (mono)
    });

    test('wavBytesStereo: a valid 2-channel PCM16 header', () {
      final interleaved =
          Int16List.fromList([100, -100, 200, -200]); // 2 frames
      final wav = wavBytesStereo(interleaved);
      expect(_u16(wav, 22), 2); // numChannels
      expect(_u32(wav, 24), kSampleRate); // sampleRate
      expect(_u32(wav, 28), kSampleRate * 4); // byteRate = sr * channels * 2
      expect(_u16(wav, 32), 4); // blockAlign = channels * 2
      expect(wav.length, 44 + interleaved.length * 2); // header + PCM16 data
    });

    test('mixStemsStereo: centre → L==R; hard pans → the far side ≈ 0', () {
      final sig = Float64List.fromList([
        for (var i = 0; i < 1000; i++) sin(2 * pi * 220 * i / kSampleRate),
      ]);

      final centre = mixStemsStereo(
        [(samples: sig, gain: 0.8, pan: 0.0)],
        totalSamples: 1000,
      );
      expect(centre.length, 2000); // interleaved L,R
      for (var i = 0; i < 1000; i++) {
        expect(centre[i * 2], centre[i * 2 + 1]); // L == R at centre
      }

      final left = mixStemsStereo(
        [(samples: sig, gain: 0.8, pan: -1.0)],
        totalSamples: 1000,
      );
      var lE = 0.0, rE = 0.0;
      for (var i = 0; i < 1000; i++) {
        lE += left[i * 2].abs();
        rE += left[i * 2 + 1].abs();
      }
      expect(lE, greaterThan(rE * 10)); // hard left → L carries it, R ≈ 0

      final right = mixStemsStereo(
        [(samples: sig, gain: 0.8, pan: 1.0)],
        totalSamples: 1000,
      );
      var lE2 = 0.0, rE2 = 0.0;
      for (var i = 0; i < 1000; i++) {
        lE2 += right[i * 2].abs();
        rE2 += right[i * 2 + 1].abs();
      }
      expect(rE2, greaterThan(lE2 * 10)); // hard right
    });

    test('a hard-left channel pans the stereo render left; usesPan flips', () {
      final s = TrackerSong(timing: const TrackerTiming(rows: 4));
      s.engine.setCell(0, 0, const TrackerCell(midi: 60));
      s.engine.setChannelPan(0, -1.0);
      s.syncCurrent();
      expect(s.usesPan, isTrue);

      final wav = s.renderCurrentPatternWav();
      expect(_u16(wav, 22), 2); // stereo now
      final data = ByteData.sublistView(wav);
      var lE = 0.0, rE = 0.0;
      for (var i = 44; i + 3 < wav.length; i += 4) {
        lE += data.getInt16(i, Endian.little).abs();
        rE += data.getInt16(i + 2, Endian.little).abs();
      }
      expect(lE, greaterThan(rE * 4)); // clearly panned left
    });
  });
}
