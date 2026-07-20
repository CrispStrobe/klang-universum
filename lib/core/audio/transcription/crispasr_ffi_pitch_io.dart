// Native CrispASR CREPE F0 via the `crispasr` package FFI (CrispasrSession.pitch,
// ggml CREPE — MIT). Resolves the crepe GGUF through CrispASR's OWN registry +
// cache (cstr/crepe-GGUF — same mechanism the TTS backend uses, no hand-rolled
// URLs), opens a pitch session, and maps its frames straight onto our
// PitchTrack (crispasr's PitchFrame is the identical record type). dart:io only.
//
// Everything is defensive: no native lib, no `crispasr_session_pitch` symbol
// (older build), no crepe model registered, or no cached/downloaded GGUF ⇒ null,
// so the caller falls back to the CLI provider and then the ONNX/pyin paths.
// Under `flutter test`/`dart run` the lib usually isn't loadable ⇒ null.

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/route.dart'
    show F0Estimator;
// crispasr also exports a `PitchFrame` typedef identical to ours — hide it so
// our contract's name wins (the returned records are structurally the same).
import 'package:crispasr/crispasr.dart' hide PitchFrame;

const int _sr16k = 16000;

/// A CrispASR-FFI CREPE [F0Estimator], or null when the ggml runtime/model
/// isn't available here. With [download] false the crepe GGUF is used only if
/// already cached; true fetches it via CrispASR's downloader.
Future<F0Estimator?> crispasrFfiCrepeF0({bool download = false}) async {
  final lib = _openLib();
  if (lib == null) return null;
  // Resolve the crepe GGUF via CrispASR's registry + cache.
  final RegistryEntry? entry = registryLookup('crepe', lib: lib);
  if (entry == null) return null; // this native build has no crepe registered
  final dir = cacheDir(lib: lib);
  final cached = dir == null ? null : File('$dir/${entry.filename}');
  String? modelPath;
  if (cached != null && cached.existsSync() && cached.lengthSync() > 0) {
    modelPath = cached.path;
  } else if (download) {
    modelPath = cacheEnsureFile(entry.filename, entry.url, lib: lib);
  }
  if (modelPath == null) return null;

  final CrispasrSession session;
  try {
    session = CrispasrSession.open(
      modelPath,
      libPath: _libPath(),
      backend: 'crepe',
    );
  } catch (_) {
    return null; // model not pitch-capable / open failed
  }

  return (Float64List mono, int sampleRate) async {
    if (mono.isEmpty) return const <PitchFrame>[];
    final at16k =
        sampleRate == _sr16k ? mono : resampleLinear(mono, sampleRate / _sr16k);
    final pcm = Float32List(at16k.length);
    for (var i = 0; i < at16k.length; i++) {
      pcm[i] = at16k[i].toDouble();
    }
    try {
      // crispasr's PitchFrame == our PitchFrame (same record shape) → the
      // returned list already satisfies PitchTrack.
      return session.pitch(pcm);
    } catch (_) {
      return const <PitchFrame>[];
    }
  };
}

/// Absolute path of libcrispasr — env override, then a built macOS app's
/// Frameworks dir, then a dev drop in the cache dir, then the package default.
/// Mirrors KokoroModelStore.libPath() (one libcrispasr for the whole app).
String _libPath() {
  final ov = Platform.environment['COMET_CRISPASR_LIB'];
  if (ov != null && ov.isNotEmpty) return ov;
  if (Platform.isMacOS) {
    try {
      final macos = File(Platform.resolvedExecutable).parent; // Contents/MacOS
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
  return CrispASR.defaultLibName();
}

DynamicLibrary? _openLib() {
  try {
    return DynamicLibrary.open(_libPath());
  } catch (_) {
    return null;
  }
}
