// Optical Music Recognition (OMR) — the app-side glue that turns a photo or
// scan of sheet music into a [Score].
//
// The recognition itself is done by an injectable [OmrEngine] (native CrispEmbed
// ggml via FFI today — see crispembed_ffi_omr.dart; a pure-Dart ONNX engine can
// drop in behind the same seam later). THIS file is the pure-Dart, testable
// glue around that engine:
//   • decode an encoded image (PNG/JPEG/…) into the grayscale [OmrImage] buffer
//     an engine consumes, and
//   • route the engine's token output through the right crisp_notation parser by
//     sniffing its dialect (SMT `bekern` / TrOMR semantic / Flova lilyNotes).
//
// Keeping this Flutter-free and model-free means the whole image→Score chain is
// unit-testable: feed a known token string and assert on the [Score].

import 'dart:typed_data';

import 'package:comet_beat/features/workshop/omr/crispembed_ffi_omr.dart';
import 'package:comet_beat/features/workshop/omr/omr_engine.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show
        MultiPartScore,
        OmrDialect,
        OmrEngine,
        OmrImage,
        Score,
        bekernToScore,
        bekernToStaffSystem,
        omrDialectOf,
        scoreFromLilyNotes,
        scoreFromSemantic;
import 'package:image/image.dart' as img;

/// Decodes encoded image [bytes] (PNG/JPEG/BMP/GIF/TIFF…) into a single-channel
/// grayscale [OmrImage] the engine can consume. Returns null when [bytes] aren't
/// a decodable image (the caller then shows "couldn't read that image").
OmrImage? imageBytesToOmr(Uint8List bytes) {
  // decodeImage can *throw* (not just return null) on malformed data as a codec
  // reads past the end — treat any failure as "not a decodable image".
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object {
    return null;
  }
  if (decoded == null) return null;
  final gray = decoded.numChannels == 1 ? decoded : img.grayscale(decoded);
  final w = gray.width;
  final h = gray.height;
  final buf = Uint8List(w * h);
  var i = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      buf[i++] = gray.getPixel(x, y).r.toInt();
    }
  }
  return OmrImage(buf, width: w, height: h); // single channel (the default)
}

/// Routes OMR [tokens] to a [Score] via the parser for their dialect. An engine
/// can emit any of the three (SMT `bekern`, TrOMR semantic, Flova lilyNotes), so
/// we sniff with [omrDialectOf] rather than assume. Throws on unparseable input.
Score omrTokensToScore(String tokens) {
  final t = tokens.trim();
  return switch (omrDialectOf(t)) {
    OmrDialect.semantic => scoreFromSemantic(t),
    OmrDialect.lilyNotes => scoreFromLilyNotes(t),
    OmrDialect.bekern => bekernToScore(t),
  };
}

/// Like [omrTokensToScore] but keeps every spine: a multi-spine `bekern` grand
/// staff becomes one part per staff (the shape the Workshop's multi-part
/// document wants); the single-staff dialects (semantic / lilyNotes) become a
/// one-part score. Throws on unparseable input.
MultiPartScore omrTokensToMultiPart(String tokens) {
  final t = tokens.trim();
  return switch (omrDialectOf(t)) {
    OmrDialect.bekern => MultiPartScore.fromStaffSystem(bekernToStaffSystem(t)),
    OmrDialect.semantic => MultiPartScore([scoreFromSemantic(t)]),
    OmrDialect.lilyNotes => MultiPartScore([scoreFromLilyNotes(t)]),
  };
}

/// Decodes [bytes], runs [engine] (or the native CrispEmbed engine, downloading
/// its GGUF when [download]) and returns the trimmed token string — or null,
/// never throwing, when the image is undecodable, no recognizer is present
/// (offline/web), or recognition is empty. Frees a self-created native engine.
Future<String?> _recogniseTokens(
  Uint8List bytes,
  OmrEngine? engine,
  bool download,
) async {
  final image = imageBytesToOmr(bytes);
  if (image == null) return null;
  final own = engine == null;
  final eng = engine ?? await crispembedFfiOmr(download: download);
  if (eng == null) return null; // no recognizer available here
  try {
    final tokens = (await eng.recognize(image)).trim();
    return tokens.isEmpty ? null : tokens;
  } on Object {
    return null; // recognition failure
  } finally {
    if (own && eng is DisposableOmrEngine) eng.dispose();
  }
}

/// Full pipeline: encoded image [bytes] → a single [Score]. See [_recogniseTokens]
/// for the null cases. Use [omrImageToMultiPart] to keep grand-staff spines.
Future<Score?> omrImageToScore(
  Uint8List bytes, {
  OmrEngine? engine,
  bool download = true,
}) async {
  final tokens = await _recogniseTokens(bytes, engine, download);
  if (tokens == null) return null;
  try {
    return omrTokensToScore(tokens);
  } on Object {
    return null; // unparseable tokens
  }
}

/// Full pipeline: encoded image [bytes] → a [MultiPartScore] (grand-staff spines
/// preserved). Null on the same cases as [omrImageToScore].
Future<MultiPartScore?> omrImageToMultiPart(
  Uint8List bytes, {
  OmrEngine? engine,
  bool download = true,
}) async {
  final tokens = await _recogniseTokens(bytes, engine, download);
  if (tokens == null) return null;
  try {
    return omrTokensToMultiPart(tokens);
  } on Object {
    return null; // unparseable tokens
  }
}
