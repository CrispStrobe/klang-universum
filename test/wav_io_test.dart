// wav_io.dart — the RIFF/WAVE PCM16 reader. The streaming_analyzer test covers
// one mono roundtrip + a too-short rejection; this pins the branches it doesn't:
// non-PCM/non-16-bit rejection, the "no data chunk" throw, the stereo→mono
// downmix, the truncated-data clamp, the multi-chunk word-aligned walk, and the
// channels<1 guard in wavToMonoFloat.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:flutter_test/flutter_test.dart';

/// Assemble a WAV byte stream with full control over the fmt header and chunks.
Uint8List _wav({
  int audioFormat = 1,
  int channels = 1,
  int sampleRate = 44100,
  int bitsPerSample = 16,
  List<int> pcm16 = const [0, 0],
  List<int>? rawData, // exact data-chunk bytes (for non-16-bit depths)
  int? dataSizeOverride, // claim a different data size than is actually present
  bool includeData = true,
  String? extraChunkId, // a chunk inserted before 'data' (tests the walk)
  int extraChunkBytes = 0,
}) {
  final b = BytesBuilder();
  void u16(int v) => b.add([v & 0xff, (v >> 8) & 0xff]);
  void u32(int v) =>
      b.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
  void str(String s) => b.add(s.codeUnits);

  final pcmBytes = rawData ??
      <int>[
        for (final s in pcm16) ...[s & 0xff, (s >> 8) & 0xff],
      ];

  str('RIFF');
  u32(0); // riff size — the reader ignores it
  str('WAVE');

  str('fmt ');
  u32(16);
  u16(audioFormat);
  u16(channels);
  u32(sampleRate);
  u32(sampleRate * channels * bitsPerSample ~/ 8); // byteRate
  u16(channels * bitsPerSample ~/ 8); // blockAlign
  u16(bitsPerSample);

  if (extraChunkId != null) {
    str(extraChunkId);
    u32(extraChunkBytes);
    b.add(List.filled(extraChunkBytes, 0));
    if (extraChunkBytes & 1 == 1) b.add([0]); // word-alignment pad
  }

  if (includeData) {
    str('data');
    u32(dataSizeOverride ?? pcmBytes.length);
    b.add(pcmBytes);
  }
  return b.toBytes();
}

void main() {
  test('reads a valid mono PCM16 clip', () {
    final wav = readWavPcm16(_wav(pcm16: [100, -200, 300], sampleRate: 22050));
    expect(wav.channels, 1);
    expect(wav.sampleRate, 22050);
    expect(wav.samples, [100, -200, 300]);
  });

  test('rejects a non-PCM (float) format', () {
    expect(() => readWavPcm16(_wav(audioFormat: 3)), throwsFormatException);
  });

  test('rejects an unsupported depth and a compressed format', () {
    // 12-bit isn't a thing we decode…
    expect(
      () => readWavPcm16(_wav(bitsPerSample: 12)),
      throwsFormatException,
    );
    // …nor is a compressed encoding (0x11 = IMA ADPCM).
    expect(
      () => readWavPcm16(_wav(audioFormat: 0x11)),
      throwsFormatException,
    );
  });

  // Real sample libraries ship more than PCM16 — ~a third of VCSL is 24-bit,
  // and these used to be rejected outright. Each depth normalizes to PCM16.
  test('decodes 24-bit PCM (the common sample-library depth)', () {
    final wav = readWavPcm16(
      _wav(
        bitsPerSample: 24,
        // LE 24-bit: +0x400000 → 16384, and 0xC00000 (negative) → -16384.
        rawData: const [0x00, 0x00, 0x40, 0x00, 0x00, 0xC0],
      ),
    );
    expect(wav.samples, [16384, -16384]);
  });

  test('decodes 8-bit PCM (unsigned, centred on 128)', () {
    final wav = readWavPcm16(
      _wav(bitsPerSample: 8, rawData: const [128, 255, 0]),
    );
    expect(wav.samples, [0, 32512, -32768]);
  });

  test('decodes 32-bit IEEE float', () {
    final bytes = Uint8List(12);
    final view = ByteData.sublistView(bytes);
    view.setFloat32(0, 1.0, Endian.little);
    view.setFloat32(4, -1.0, Endian.little);
    view.setFloat32(8, 0.5, Endian.little);
    final wav = readWavPcm16(
      _wav(audioFormat: 3, bitsPerSample: 32, rawData: bytes),
    );
    expect(wav.samples, [32767, -32767, 16384]);
  });

  test('accepts WAVE_FORMAT_EXTENSIBLE (0xFFFE), which 24-bit writers use', () {
    final wav = readWavPcm16(
      _wav(
        audioFormat: 0xFFFE,
        bitsPerSample: 24,
        rawData: const [0x00, 0x00, 0x40],
      ),
    );
    expect(wav.samples, [16384]);
  });

  test('rejects a file with no data chunk', () {
    // fmt only + a filler chunk so the file still clears the 44-byte minimum.
    final bytes = _wav(
      includeData: false,
      extraChunkId: 'LIST',
      extraChunkBytes: 16,
    );
    expect(bytes.length, greaterThanOrEqualTo(44));
    expect(() => readWavPcm16(bytes), throwsFormatException);
  });

  test('finds data after an odd-sized chunk (word alignment)', () {
    // An odd-length chunk before 'data' — the reader must apply the pad byte
    // (size & 1) or it lands mid-chunk and never sees 'data'.
    final wav = readWavPcm16(
      _wav(pcm16: [7, 8], extraChunkId: 'fact', extraChunkBytes: 3),
    );
    expect(wav.samples, [7, 8]);
  });

  test('clamps a data chunk that claims more bytes than are present', () {
    // Header says 999 bytes of data but only 2 samples (4 bytes) follow.
    final wav = readWavPcm16(_wav(pcm16: [11, 22], dataSizeOverride: 999));
    expect(wav.samples, [11, 22]); // no over-read, no throw
  });

  test('downmixes stereo to mono by averaging channels', () {
    // Two frames: (1000, 3000) and (-4000, -2000) → averages 2000, -3000.
    final wav = readWavPcm16(
      _wav(channels: 2, pcm16: [1000, 3000, -4000, -2000]),
    );
    expect(wav.channels, 2);
    final mono = wavToMonoFloat(wav);
    expect(mono, hasLength(2));
    expect(mono[0], closeTo(2000 / 32768.0, 1e-9));
    expect(mono[1], closeTo(-3000 / 32768.0, 1e-9));
  });

  test('wavToMonoFloat guards a zero channel count', () {
    final wav = WavData(
      samples: Int16List.fromList([16384, -16384]),
      sampleRate: 44100,
      channels: 0, // a malformed header must not divide by zero
    );
    final mono = wavToMonoFloat(wav);
    expect(mono, hasLength(2));
    expect(mono[0], closeTo(0.5, 1e-9));
    expect(mono[1], closeTo(-0.5, 1e-9));
  });

  test(
      'a "fmt " chunk within 16 bytes of EOF throws FormatException, not '
      'RangeError', () {
    // The chunk walk only guarantees the 8-byte chunk header fits, but the fmt
    // body is 16 bytes. Craft a 44-byte file whose chunk walk lands a "fmt " id
    // at offset 36 (body 44 = EOF): reading the fmt fields would run off the
    // buffer. The reader's contract is FormatException on anything unreadable.
    final b = Uint8List(44);
    final d = ByteData.sublistView(b);
    b.setRange(0, 4, 'RIFF'.codeUnits);
    b.setRange(8, 12, 'WAVE'.codeUnits);
    // chunk @12: "JUNK" size=16 -> next chunk at 12 + 8 + 16 = 36
    b.setRange(12, 16, 'JUNK'.codeUnits);
    d.setUint32(16, 16, Endian.little);
    // chunk @36: "fmt " id, header fits (p+8=44) but body+16 = 60 > 44
    b.setRange(36, 40, 'fmt '.codeUnits);
    d.setUint32(40, 16, Endian.little);
    expect(() => readWavPcm16(b), throwsFormatException);
    expect(() => readWavPcm16(b), throwsA(isNot(isA<RangeError>())));
  });
}
