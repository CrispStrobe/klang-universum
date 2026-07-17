// lib/core/audio/mod/mod_reader.dart
//
// ProTracker `.mod` IMPORT (reader): raw bytes → [ModModule]. Pure Dart.
// Implement against the byte-layout contract documented in mod_module.dart.
//
// Contract:
//   • Parse the 20-byte title, 31 sample descriptors, song length + restart +
//     128-byte order table, the 4-byte signature (→ channelCount), the patterns
//     (count = max order entry + 1; 64 rows × channelCount × 4 bytes), then the
//     per-sample signed-8-bit PCM.
//   • Convert word lengths (×2) to samples/bytes; decode finetune as a signed
//     4-bit value; decode each cell (sample/period/effect/param) per the spec.
//   • `order` in the result has length = song length (the used positions only).
//   • Throw [ModFormatException] when the input is too short or the signature is
//     not a known MOD tag.
//   • Round-trip: `writeMod(parseMod(bytes))` must reproduce the same
//     [ModModule] (see test/mod_codec_test.dart golden fixtures).

import 'dart:typed_data';

import 'package:klang_universum/core/audio/mod/mod_module.dart';

/// Parses ProTracker `.mod` [bytes] into a [ModModule].
ModModule parseMod(Uint8List bytes) {
  throw UnimplementedError('parseMod: implemented by the import agent');
}
