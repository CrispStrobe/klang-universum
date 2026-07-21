// Native CrispASR TabCNN emitter — audio → [TabEmissionFrames] via libcrispasr's
// ggml `--tab` backend (crispasr v0.8.18), bound with raw dart:ffi against the
// `crispasr_session_tab*` C ABI (docs/TABCNN_GGML_HANDBACK.md §1). No dependency
// on a Dart `.tab()` wrapper. The gpfx GGUF (cstr/tabcnn-GGUF, F16 head) is
// resolved + cached from HF; the lib path mirrors crispasr_ffi_pitch_io.
//
// Everything is defensive: no lib, missing symbol, no/failed session, or no
// cached/downloaded GGUF ⇒ null, so the resolver falls back to the pure-Dart
// onnx path. Carries the model's `silent_class` into [TabEmissionFrames] (§2 —
// the GGUF keeps upstream order, silent = 20, NOT the onnx-remapped 0).

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/features/games/composition/tab_emission_decoder.dart';
import 'package:ffi/ffi.dart';

// --- C ABI signatures (crispasr_session.h) ---------------------------------
typedef _OpenNative = Pointer<Void> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Int32,
);
typedef _OpenDart = Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>, int);
typedef _TabNative = Int32 Function(
  Pointer<Void>,
  Pointer<Float>,
  Int32,
  Int32,
);
typedef _TabDart = int Function(Pointer<Void>, Pointer<Float>, int, int);
typedef _EmitNative = Pointer<Float> Function(
  Pointer<Void>,
  Pointer<Int32>,
  Pointer<Int32>,
  Pointer<Int32>,
);
typedef _EmitDart = Pointer<Float> Function(
  Pointer<Void>,
  Pointer<Int32>,
  Pointer<Int32>,
  Pointer<Int32>,
);
typedef _IntNative = Int32 Function(Pointer<Void>);
typedef _IntDart = int Function(Pointer<Void>);
typedef _FloatNative = Float Function(Pointer<Void>);
typedef _FloatDart = double Function(Pointer<Void>);
typedef _CloseNative = Void Function(Pointer<Void>);
typedef _CloseDart = void Function(Pointer<Void>);

const _ggufUrl =
    'https://huggingface.co/cstr/tabcnn-GGUF/resolve/main/tabcnn-f16.gguf';
const _ggufName = 'tabcnn-f16.gguf';

/// The native TabCNN emitter as a [TabEmissionModel], or null when the ggml
/// lib/GGUF isn't available here (no lib, no symbol, offline). With [download]
/// false the GGUF is used only if already cached; true fetches it. Call
/// `.dispose()` when done to free the session.
Future<TabEmissionModel?> crispasrFfiTab({bool download = false}) async {
  final DynamicLibrary lib;
  try {
    lib = DynamicLibrary.open(_libPath());
  } catch (_) {
    return null;
  }

  final modelPath = await _ensureGguf(download: download);
  if (modelPath == null) return null;

  try {
    final open = lib.lookupFunction<_OpenNative, _OpenDart>(
      'crispasr_session_open_explicit',
    );
    final backend = 'tabcnn'.toNativeUtf8();
    final mp = modelPath.toNativeUtf8();
    final Pointer<Void> session;
    try {
      final threads = Platform.numberOfProcessors.clamp(1, 8);
      session = open(mp, backend, threads);
    } finally {
      malloc
        ..free(backend)
        ..free(mp);
    }
    if (session == nullptr) return null;
    return CrispasrFfiTab._(
      session,
      lib.lookupFunction<_TabNative, _TabDart>('crispasr_session_tab'),
      lib.lookupFunction<_EmitNative, _EmitDart>(
        'crispasr_session_tab_emissions',
      ),
      lib.lookupFunction<_IntNative, _IntDart>(
        'crispasr_session_tab_silent_class',
      ),
      lib.lookupFunction<_FloatNative, _FloatDart>(
        'crispasr_session_tab_frame_period',
      ),
      lib.lookupFunction<_CloseNative, _CloseDart>('crispasr_session_close'),
    );
  } catch (_) {
    return null; // missing symbol on an older lib, etc.
  }
}

/// A [TabEmissionModel] backed by the native ggml session. Holds the session
/// open across [emit] calls; [dispose] frees it.
class CrispasrFfiTab implements TabEmissionModel {
  CrispasrFfiTab._(
    this._session,
    this._tab,
    this._emissions,
    this._silent,
    this._period,
    this._close,
  );

  final Pointer<Void> _session;
  final _TabDart _tab;
  final _EmitDart _emissions;
  final _IntDart _silent;
  final _FloatDart _period;
  final _CloseDart _close;
  bool _closed = false;

  @override
  TabEmissionFrames? emit(Float64List monoAudio, int sampleRate) {
    if (_closed || monoAudio.isEmpty) return null;
    final n = monoAudio.length;
    // The backend resamples any sample rate to its 22050 — pass mono as-is.
    final pcm = malloc<Float>(n);
    try {
      for (var i = 0; i < n; i++) {
        pcm[i] = monoAudio[i].toDouble();
      }
      final nf = _tab(_session, pcm, n, sampleRate);
      if (nf <= 0) return null;
      final onf = malloc<Int32>(), ons = malloc<Int32>(), onc = malloc<Int32>();
      try {
        final ptr = _emissions(_session, onf, ons, onc);
        final frames = onf.value, strings = ons.value, classes = onc.value;
        // The decoder's flat layout is fixed at 6×21; bail if the model differs.
        if (ptr == nullptr ||
            strings != kTabStrings ||
            classes != kTabClasses ||
            frames <= 0) {
          return null;
        }
        final len = frames * strings * classes;
        final buf = Float64List(len);
        for (var i = 0; i < len; i++) {
          buf[i] = ptr[i];
        }
        return TabEmissionFrames(
          nFrames: frames,
          hopSeconds: _period(_session),
          logProbs: buf,
          silentClass: _silent(_session), // §2: GGUF native order (20)
        );
      } finally {
        malloc
          ..free(onf)
          ..free(ons)
          ..free(onc);
      }
    } finally {
      malloc.free(pcm);
    }
  }

  /// Frees the native session. Idempotent.
  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _close(_session);
  }
}

/// libcrispasr path — env override, then a built macOS app's Frameworks dir,
/// then a dev drop, then the platform default. Mirrors crispasr_ffi_pitch_io.
String _libPath() {
  final ov = Platform.environment['COMET_CRISPASR_LIB'];
  if (ov != null && ov.isNotEmpty) return ov;
  if (Platform.isMacOS) {
    try {
      final macos = File(Platform.resolvedExecutable).parent;
      final bundled = '${macos.parent.path}/Frameworks/libcrispasr.dylib';
      if (File(bundled).existsSync()) return bundled;
    } catch (_) {
      // fall through
    }
  }
  final home = Platform.environment['HOME'];
  if (home != null) {
    final drop = '$home/.cache/crispasr/libcrispasr.dylib';
    if (File(drop).existsSync()) return drop;
  }
  return Platform.isMacOS
      ? 'libcrispasr.dylib'
      : (Platform.isWindows ? 'crispasr.dll' : 'libcrispasr.so');
}

String _ggufDir() {
  final env = Platform.environment['COMET_TABCNN_GGUF_DIR'];
  if (env != null && env.isNotEmpty) return env;
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.systemTemp.path;
  return '$home/.cache/comet_beat/models';
}

/// The cached tabcnn GGUF path, downloading on first use when [download].
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
    client.userAgent = 'comet_beat-tabcnn';
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
