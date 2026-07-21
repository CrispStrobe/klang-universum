// Native CrispEmbed OMR engine — a sheet-music image → `bekern` tokens via
// libcrispembed's ggml OCR backend, bound with raw dart:ffi against the
// `crispembed_ocr_model_*` C ABI (mirrors crispembed_omr.dart in
// crisp_notation_cli, and the crispasr_ffi_* providers in this app).
//
// Everything is defensive: no lib, missing symbol, failed init, or no
// cached/downloaded GGUF ⇒ null, so the caller reports "on-device OMR isn't
// available" instead of crashing. The SMT GrandStaff GGUF (cstr/
// smt-grandstaff-GGUF) is resolved + cached from HF; the lib path mirrors
// crispasr_ffi_tab_io.

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/features/workshop/omr/omr_engine.dart';
import 'package:crisp_notation/crisp_notation.dart' show OmrEngine, OmrImage;
import 'package:ffi/ffi.dart';

// --- C ABI signatures (crispembed_ocr_model_*) -----------------------------
typedef _InitNative = Pointer<Void> Function(Pointer<Utf8>, Int32);
typedef _InitDart = Pointer<Void> Function(Pointer<Utf8>, int);
typedef _RecognizeNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Uint8>,
  Int32,
  Int32,
  Int32,
  Pointer<Int32>,
);
typedef _RecognizeDart = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Uint8>,
  int,
  int,
  int,
  Pointer<Int32>,
);
typedef _FreeNative = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);

// The default SMT GrandStaff model (cstr/smt-grandstaff-GGUF).
const _ggufUrl = 'https://huggingface.co/cstr/smt-grandstaff-GGUF/'
    'resolve/main/smt-grandstaff-q8_0.gguf';
const _ggufName = 'smt-grandstaff-q8_0.gguf';

/// The native CrispEmbed OMR engine as an [OmrEngine], or null when the ggml
/// lib/GGUF isn't available here (no lib, no symbol, offline). With [download]
/// false the GGUF is used only if already cached; true fetches it. The returned
/// engine is a [DisposableOmrEngine] — free it after use.
Future<OmrEngine?> crispembedFfiOmr({bool download = false}) async {
  final DynamicLibrary lib;
  try {
    lib = DynamicLibrary.open(_libPath());
  } catch (_) {
    return null;
  }

  final modelPath = await _ensureGguf(download: download);
  if (modelPath == null) return null;

  try {
    final init =
        lib.lookupFunction<_InitNative, _InitDart>('crispembed_ocr_model_init');
    final recognize = lib.lookupFunction<_RecognizeNative, _RecognizeDart>(
      'crispembed_ocr_model_recognize',
    );
    final free =
        lib.lookupFunction<_FreeNative, _FreeDart>('crispembed_ocr_model_free');

    final mp = modelPath.toNativeUtf8();
    final Pointer<Void> ctx;
    try {
      final threads = Platform.numberOfProcessors.clamp(1, 8);
      ctx = init(mp, threads);
    } finally {
      malloc.free(mp);
    }
    if (ctx == nullptr) return null;
    return _CrispembedFfiOmr._(ctx, recognize, free);
  } catch (_) {
    return null; // missing symbol on an older lib, etc.
  }
}

/// An [OmrEngine] backed by the native ggml OCR model. Holds the model open
/// across [recognize] calls; [dispose] frees it.
class _CrispembedFfiOmr implements DisposableOmrEngine {
  _CrispembedFfiOmr._(this._ctx, this._recognize, this._free);

  final Pointer<Void> _ctx;
  final _RecognizeDart _recognize;
  final _FreeDart _free;
  bool _disposed = false;

  @override
  Future<String> recognize(OmrImage image) async {
    if (_disposed) return '';
    final n = image.pixels.length;
    final buf = malloc<Uint8>(n);
    final outLen = malloc<Int32>();
    try {
      buf.asTypedList(n).setAll(0, image.pixels);
      final res = _recognize(
        _ctx,
        buf,
        image.width,
        image.height,
        image.channels,
        outLen,
      );
      if (res == nullptr) return '';
      return res.toDartString(); // native owns the buffer (as in the CLI)
    } catch (_) {
      return '';
    } finally {
      malloc
        ..free(buf)
        ..free(outLen);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _free(_ctx);
  }
}

/// libcrispembed path — env override, then a built macOS app's Frameworks dir,
/// then a dev drop, then the platform default. Mirrors crispasr_ffi_tab_io.
String _libPath() {
  final ov = Platform.environment['COMET_CRISPEMBED_LIB'] ??
      Platform.environment['CRISPEMBED_LIB'];
  if (ov != null && ov.isNotEmpty) return ov;
  if (Platform.isMacOS) {
    try {
      final macos = File(Platform.resolvedExecutable).parent;
      final bundled = '${macos.parent.path}/Frameworks/libcrispembed.dylib';
      if (File(bundled).existsSync()) return bundled;
    } catch (_) {
      // fall through
    }
  }
  final home = Platform.environment['HOME'];
  if (home != null) {
    final drop = '$home/.cache/crispembed/libcrispembed.dylib';
    if (File(drop).existsSync()) return drop;
  }
  return Platform.isMacOS
      ? 'libcrispembed.dylib'
      : (Platform.isWindows ? 'crispembed.dll' : 'libcrispembed.so');
}

String _ggufDir() {
  final env = Platform.environment['COMET_OMR_GGUF_DIR'];
  if (env != null && env.isNotEmpty) return env;
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.systemTemp.path;
  return '$home/.cache/comet_beat/models';
}

/// The cached OMR GGUF path, downloading on first use when [download].
Future<String?> _ensureGguf({required bool download}) async {
  final file = File('${_ggufDir()}/$_ggufName');
  if (file.existsSync() && file.lengthSync() > 100000) return file.path;
  if (!download) return null;
  try {
    Directory(_ggufDir()).createSync(recursive: true);
    final bytes = await _get(_ggufUrl);
    if (bytes == null || bytes.length < 100000) return null;
    await file.writeAsBytes(bytes);
    return file.path;
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> _get(String url) async {
  final client = HttpClient();
  try {
    client.userAgent = 'comet_beat-omr';
    var uri = Uri.parse(url);
    for (var hop = 0; hop < 5; hop++) {
      final req = await client.getUrl(uri);
      req.followRedirects = false;
      final resp = await req.close();
      if (resp.statusCode == 200) {
        final b = BytesBuilder(copy: false);
        await for (final chunk in resp) {
          b.add(chunk);
        }
        return b.takeBytes();
      }
      final loc = resp.headers.value(HttpHeaders.locationHeader);
      await resp.drain<void>();
      if (resp.isRedirect && loc != null) {
        uri = Uri.parse(loc);
        continue;
      }
      return null;
    }
    return null;
  } finally {
    client.close();
  }
}
