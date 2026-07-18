// Pure-Dart MP3 encoder — slice 1 (bit writer + frame header + framing math).
// Verified against the known MPEG-1 Layer III bitstream layout (ISO 11172-3).

import 'package:comet_beat/core/audio/mp3/mp3_bitstream.dart';
import 'package:comet_beat/core/audio/mp3/mp3_frame.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Mp3BitWriter (MSB-first)', () {
    test('packs bits big-endian', () {
      final w = Mp3BitWriter()
        ..writeBits(0xF, 4) // 1111
        ..writeBits(0x0, 4); // 0000
      expect(w.takeBytes(), [0xF0]);
    });

    test('splits writes larger than 25 bits', () {
      final w = Mp3BitWriter()..writeBits(0xFFFFFFF, 28); // 28 ones
      final bytes = w.takeBytes();
      expect(bytes, [0xFF, 0xFF, 0xFF, 0xF0]); // 28 ones, right-padded
    });

    test('bit/byte counts + flush padding', () {
      final w = Mp3BitWriter()..writeBits(0x7FF, 11);
      expect(w.bitCount, 11);
      expect(w.byteCount, 2); // 11 bits -> rounds up to 2 bytes
      expect(w.takeBytes(), [0xFF, 0xE0]); // 11111111 111 -> pad
    });
  });

  group('MP3 frame header (MPEG-1 Layer III)', () {
    test('128 kbps / 44100 / stereo = FF FB 90 04', () {
      final h = mp3FrameHeader(bitrateKbps: 128, sampleRate: 44100);
      expect(h, [0xFF, 0xFB, 0x90, 0x04]);
    });

    test('320 kbps / 48000 / mono differs correctly', () {
      final h = mp3FrameHeader(
        bitrateKbps: 320,
        sampleRate: 48000,
        channelMode: Mp3ChannelMode.mono,
      );
      // sync + MPEG1 + LayerIII + noCRC -> FF FB; bitrate idx 14 (1110),
      // sr idx 1 (01), no pad, private 0 -> 1110 01 0 0 = 0xE4;
      // mono (11) + modeExt 0 (00) + copy 0 + orig 1 + emphasis 0 -> 11000100 = 0xC4.
      expect(h, [0xFF, 0xFB, 0xE4, 0xC4]);
    });

    test('rejects invalid bitrate / sample rate', () {
      expect(
        () => mp3FrameHeader(bitrateKbps: 130, sampleRate: 44100),
        throwsArgumentError,
      );
      expect(
        () => mp3FrameHeader(bitrateKbps: 128, sampleRate: 44101),
        throwsArgumentError,
      );
    });
  });

  group('framing math', () {
    test('frame size = 144 * bitrate / samplerate (+pad)', () {
      // 128k/44.1k = 417.9 -> 417, +1 with padding.
      expect(mp3FrameSize(128, 44100), 417);
      expect(mp3FrameSize(128, 44100, padding: true), 418);
      // 320k/48k = 960 exactly.
      expect(mp3FrameSize(320, 48000), 960);
    });

    test('index helpers', () {
      expect(mp3BitrateIndex(128), 9);
      expect(mp3BitrateIndex(320), 14);
      expect(mp3BitrateIndex(130), 0);
      expect(mp3SampleRateIndex(44100), 0);
      expect(mp3SampleRateIndex(32000), 2);
      expect(mp3SampleRateIndex(44101), -1);
    });
  });
}
