// Native OMR import: decode a sheet-music photo → raw pixels → the crispembed
// ggml engine → recognition tokens → a crisp_notation Score (pure-Dart parse).
// The GGUF model downloads on demand and is cached in the same dir the CLI uses,
// so a model fetched by `crisp_notation omr` is reused here.
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:crispembed/crispembed.dart' show CrispEmbedOmr;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

// The default engine: Sheet Music Transformer (grand staff → bekern). The
// dialect of whatever the model emits is auto-detected, so swapping the model
// (tromr/flova) needs no code change.
const _modelFile = 'smt-grandstaff-q8_0.gguf';
const _modelUrl =
    'https://huggingface.co/cstr/smt-grandstaff-GGUF/resolve/main/$_modelFile';

String _cacheDir() {
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.systemTemp.path;
  return '$home/.cache/crisp_notation/omr';
}

String _defaultLibName() => Platform.isMacOS
    ? 'libcrispembed.dylib'
    : Platform.isWindows
        ? 'crispembed.dll'
        : 'libcrispembed.so';

/// Absolute path of libcrispembed — env override, then a built macOS app's
/// Frameworks dir; else null (let the loader resolve the default name).
String? _libPath() {
  final ov = Platform.environment['CRISPEMBED_LIB'] ??
      Platform.environment['COMET_CRISPEMBED_LIB'];
  if (ov != null && ov.isNotEmpty) return ov;
  if (Platform.isMacOS) {
    try {
      final macos = File(Platform.resolvedExecutable).parent; // Contents/MacOS
      final bundled = '${macos.parent.path}/Frameworks/libcrispembed.dylib';
      if (File(bundled).existsSync()) return bundled;
    } catch (_) {
      // fall through
    }
  }
  return null;
}

/// Whether OMR can run here: the native crispembed library loads.
bool omrAvailable() {
  try {
    ffi.DynamicLibrary.open(_libPath() ?? _defaultLibName());
    return true;
  } catch (_) {
    return false;
  }
}

/// The cached model path, or null. [download] fetches the ~24 MB GGUF from
/// Hugging Face (consent-gated by the caller) if it isn't already cached.
Future<String?> omrModelPath({
  bool download = false,
  void Function(String message)? onStatus,
}) async {
  final path = '${_cacheDir()}/$_modelFile';
  final f = File(path);
  if (f.existsSync() && f.lengthSync() > 0) return path;
  if (!download) return null;
  try {
    onStatus?.call('Downloading recognition model…');
    Directory(_cacheDir()).createSync(recursive: true);
    final resp = await http.get(Uri.parse(_modelUrl));
    if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return null;
    final tmp = File('$path.part');
    await tmp.writeAsBytes(resp.bodyBytes, flush: true);
    tmp.renameSync(path);
    return path;
  } catch (_) {
    return null;
  }
}

/// Recognises sheet-music [imageBytes] (PNG/JPEG) → a [Score], or null when OMR
/// is unavailable, the model is absent (and [download] false), or recognition
/// yields nothing.
Future<Score?> recognizeSheetMusic(
  Uint8List imageBytes, {
  bool download = false,
  void Function(String message)? onStatus,
}) async {
  if (!omrAvailable()) return null;
  final modelPath = await omrModelPath(download: download, onStatus: onStatus);
  if (modelPath == null) return null;

  final decoded = img.decodeImage(imageBytes);
  if (decoded == null) return null;
  onStatus?.call('Reading the notes…');
  final w = decoded.width, h = decoded.height;
  final rgb = Uint8List(w * h * 3);
  var i = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = decoded.getPixel(x, y);
      rgb[i++] = p.r.toInt();
      rgb[i++] = p.g.toInt();
      rgb[i++] = p.b.toInt();
    }
  }

  final omr = CrispEmbedOmr(modelPath, libPath: _libPath());
  try {
    final tokens = omr.recognize(rgb, w, h, 3);
    if (tokens == null || tokens.trim().isEmpty) return null;
    return switch (omrDialectOf(tokens)) {
      OmrDialect.semantic => scoreFromSemantic(tokens),
      OmrDialect.lilyNotes => scoreFromLilyNotes(tokens),
      OmrDialect.bekern => bekernToScore(tokens),
    };
  } catch (_) {
    return null;
  } finally {
    omr.dispose();
  }
}
