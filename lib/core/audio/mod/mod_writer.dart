// lib/core/audio/mod/mod_writer.dart
//
// ProTracker `.mod` EXPORT (writer): [ModModule] → raw bytes. Pure Dart.
// The exact inverse of mod_reader.dart; implement against the byte-layout
// contract in mod_module.dart.
//
// Contract:
//   • Emit the 20-byte title (NUL-padded/truncated), 31 sample descriptors
//     (name, word-length = `(pcm.length + 1) ~/ 2`, finetune as a signed nibble,
//     volume, repeat point/length in words), song length, restart, the 128-byte
//     order table (order padded with 0), the "M.K." signature for 4 channels
//     (choose the right tag for other channel counts), the pattern data
//     (64 rows × channelCount × 4 bytes, cells encoded per the spec), then each
//     sample's signed-8-bit PCM in order.
//   • Numbers are BIG-ENDIAN. Pattern count written = `module.patterns.length`.
//   • Byte-stability: for a canonical module `writeMod` must reproduce the exact
//     bytes `parseMod` read (see the golden fixtures in test/mod_codec_test.dart).

import 'dart:typed_data';

import 'package:klang_universum/core/audio/mod/mod_module.dart';

/// Serializes [module] to ProTracker `.mod` bytes.
Uint8List writeMod(ModModule module) {
  throw UnimplementedError('writeMod: implemented by the export agent');
}
