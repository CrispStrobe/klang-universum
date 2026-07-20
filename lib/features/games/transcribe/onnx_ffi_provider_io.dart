// Native-ONNX-Runtime ("onnxFfi") providers. Loads the same .onnx models the
// pure-Dart path caches, but runs inference on native ORT (onnxruntime plugin)
// via the OrtFfiSession wrapper, reusing the identical Dart framing/decoding
// (crepeF0WithRunner / rmvpeF0WithRunner). Returns null when the model isn't
// cached OR the native ORT runtime can't load here (headless test / `dart run`)
// — so it's a no-op fallback everywhere except a real app build. dart:io only.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/crepe.dart'
    show crepeF0WithRunner;
import 'package:comet_beat/core/audio/transcription/crepe_model_store.dart';
import 'package:comet_beat/core/audio/transcription/harmony.dart'
    show ChordEstimator;
import 'package:comet_beat/core/audio/transcription/onnx_ort_session.dart';
import 'package:comet_beat/core/audio/transcription/rmvpe.dart'
    show rmvpeF0WithRunner;
import 'package:comet_beat/core/audio/transcription/rmvpe_mel.dart';
import 'package:comet_beat/core/audio/transcription/rmvpe_model_store.dart';
import 'package:comet_beat/core/audio/transcription/route.dart'
    show F0Estimator, NeuralTranscriber;

// Model IO tensor names (mirror the engines' private consts).
const String _crepeIn = 'frames';
const String _crepeOut = 'activation';
const int _crepeWindow = 1024;
const String _rmvpeIn = 'input';
const String _rmvpeOut = 'output';

/// Native-ORT monophonic F0: RMVPE if its bundle is cached (preferred, matching
/// the pure-Dart onnx path), else CREPE. [download] pulls the model if missing
/// (an explicit backend choice); otherwise used only if already cached. Null ⇒
/// no model or no native ORT here → the resolver falls to the pure-Dart onnx
/// path.
Future<F0Estimator?> loadOnnxFfiF0({bool download = false}) async =>
    await _rmvpeFfiF0(download: download) ??
    await _crepeFfiF0(download: download);

/// Native-ORT polyphony (Basic Pitch) — not yet wired; the pure-Dart onnx path
/// serves polyphony. Stub so the resolver treats onnxFfi as absent for poly.
Future<NeuralTranscriber?> loadOnnxFfiNeural({bool download = false}) async =>
    null;

/// Native-ORT chords (BTC) — not yet wired; the pure-Dart onnx path serves
/// chords. Stub so the resolver treats onnxFfi as absent for chords.
Future<ChordEstimator?> loadOnnxFfiChords({bool download = false}) async =>
    null;

// ── F0 backends ──────────────────────────────────────────────────────────────

Future<F0Estimator?> _rmvpeFfiF0({required bool download}) async {
  final store = RmvpeModelStore();
  if (!download && !store.isPresent()) return null;
  if (download && !await store.ensureFiles()) return null;
  if (!store.isPresent()) return null;
  final Uint8List modelBytes;
  final RmvpeMel mel;
  try {
    modelBytes = await store.modelFile().readAsBytes();
    mel = RmvpeMel.fromBytes(await store.melFile().readAsBytes());
  } catch (_) {
    return null;
  }
  final session = OrtFfiSession.fromBytes(modelBytes);
  if (session == null) return null; // native ORT not loadable here
  Float32List runRmvpe(Float32List input, int nMels, int pf) {
    final out = session.run(_rmvpeIn, input, [1, nMels, pf], const [_rmvpeOut]);
    return out[_rmvpeOut]!;
  }

  return (Float64List mono, int sampleRate) async =>
      rmvpeF0WithRunner(mono, mel: mel, sampleRate: sampleRate, run: runRmvpe);
}

Future<F0Estimator?> _crepeFfiF0({required bool download}) async {
  final bytes = await _crepeBytes(download: download);
  if (bytes == null) return null;
  final session = OrtFfiSession.fromBytes(bytes);
  if (session == null) return null; // native ORT not loadable here
  Float32List runCrepe(Float32List frames, int nf) {
    final out =
        session.run(_crepeIn, frames, [nf, _crepeWindow], const [_crepeOut]);
    return out[_crepeOut]!;
  }

  return (Float64List mono, int sampleRate) async =>
      crepeF0WithRunner(mono, sampleRate: sampleRate, run: runCrepe);
}

/// The cached CREPE .onnx bytes (downloading first if [download]), or null.
Future<Uint8List?> _crepeBytes({required bool download}) async {
  final store = CrepeModelStore();
  final File? file;
  if (download) {
    file = await store.ensureFile();
  } else {
    final cached = store.modelFile();
    file = cached.existsSync() ? cached : null;
  }
  if (file == null) return null;
  try {
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}
