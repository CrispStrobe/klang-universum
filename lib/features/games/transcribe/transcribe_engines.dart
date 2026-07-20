// Turns the user's TranscriptionEngineConfig + what's actually installed into the
// concrete engines to inject into the pipeline. This is the bridge between the
// Settings choices and route.dart's F0Estimator / NeuralTranscriber seams:
// config.resolve() decides WHICH backend a step wants; the providers decide
// whether it's actually present; anything unpicked or absent falls back to
// pure-Dart (a null engine).

import 'package:comet_beat/core/audio/transcription/crispasr_ffi_pitch.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_pitch.dart';
import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:comet_beat/core/audio/transcription/harmony.dart'
    show ChordEstimator;
import 'package:comet_beat/core/audio/transcription/route.dart'
    show F0Estimator, NeuralTranscriber;
import 'package:comet_beat/features/games/transcribe/crepe_provider.dart';
import 'package:comet_beat/features/games/transcribe/harmony_provider.dart';
import 'package:comet_beat/features/games/transcribe/neural_provider.dart';
import 'package:comet_beat/features/games/transcribe/onnx_ffi_provider.dart'
    as onnx_ffi;
import 'package:comet_beat/features/games/transcribe/rmvpe_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// The neural engines to inject for a single-recording transcription: an [f0]
/// estimator (RMVPE/CREPE) for the monophonic path, a [neural] transcriber (Basic
/// Pitch) for the polyphonic path, and a [chords] recogniser (BTC). Each null ⇒
/// use the pure-Dart default (or, for chords, none).
typedef TranscriptionEngines = ({
  F0Estimator? f0,
  NeuralTranscriber? neural,
  ChordEstimator? chords,
});

// ---------------------------------------------------------------------------
// The two native-FFI runtimes (the 2nd and 3rd of the "3 paths"). Each is a null
// STUB until its binding + libs land; un-stubbing any one is a few lines, and it
// then appears in `available` so the resolver can pick it. Until then a chosen
// FFI backend gracefully falls back to pure-Dart ONNX.
// ---------------------------------------------------------------------------

/// `crispasr` runtime — CREPE F0 via CrispASR ggml. Prefers the in-app FFI
/// binding (`crispasr_ffi_pitch.dart` → `CrispasrSession.pitch`, crispasr
/// 0.8.16+; model auto-resolved via CrispASR's registry, cstr/crepe-GGUF), and
/// falls back to the `crispasr --pitch` CLI (`crispasr_pitch.dart`, env-gated)
/// for dev without a bundled lib. Null → the resolver falls to the ONNX F0 path.
Future<F0Estimator?> loadCrispasrCrepeF0({bool download = false}) async =>
    await crispasrFfiCrepeF0(download: download) ?? crispasrCliCrepeF0();

/// `crispasr` runtime — polyphonic transcription via CrispASR ggml PIANO (Kong).
/// Returns [NoteEvent]s. Piano is session-openable today, but its only output is
/// segment text ("C4 v=80") — lossy/ugly to parse. Deliberately still stubbed:
/// CrispASR is adding a clean `crispasr_session_piano_notes*` C ABI returning
/// {midi, onMs, offMs, velocity} (their §251), which drops straight onto
/// [NoteEvent]. Un-stub against THAT, not the text hack. Until then, the
/// pure-Dart onnx Basic Pitch serves polyphony.
Future<NeuralTranscriber?> loadCrispasrPiano({bool download = false}) async =>
    null;

/// `onnxFfi` runtime — the same CREPE `.onnx` model on the NATIVE ONNX Runtime
/// via FFI (the `onnxruntime` plugin), reusing crepeF0WithRunner. WIRED for F0
/// (`onnx_ffi_provider.dart`): live in a desktop/mobile app build with the CREPE
/// model cached; null elsewhere (web / headless / model absent) → falls back to
/// the pure-Dart onnx F0 path.
Future<F0Estimator?> loadOnnxFfiF0({bool download = false}) =>
    onnx_ffi.loadOnnxFfiF0(download: download);

/// `onnxFfi` runtime — Basic Pitch `.onnx` on the native ONNX Runtime. Not yet
/// wired (the pure-Dart onnx path serves polyphony); stub via the provider.
Future<NeuralTranscriber?> loadOnnxFfiNeural({bool download = false}) =>
    onnx_ffi.loadOnnxFfiNeural(download: download);

/// `onnxFfi` runtime — BTC chords `.onnx` on the native ONNX Runtime. Not yet
/// wired (the pure-Dart onnx path serves chords); stub via the provider.
Future<ChordEstimator?> loadOnnxFfiChords({bool download = false}) =>
    onnx_ffi.loadOnnxFfiChords(download: download);

/// Resolve the engines from [config], probing every RUNTIME for every step and
/// honouring the per-step backend choice. Each step can run on up to three
/// neural runtimes (config.resolve prefers ggml > native-ORT FFI > pure-Dart
/// ONNX):
///   • F0        — pure-Dart ONNX: RMVPE (preferred) or CREPE; native-ORT FFI
///     (stub); ggml CREPE (stub).
///   • polyphony — pure-Dart ONNX: Basic Pitch; native-ORT FFI (stub); ggml
///     piano (stub).
///   • chords    — pure-Dart ONNX: BTC; native-ORT FFI (stub). (No ggml yet.)
/// An explicit (non-auto) choice downloads its model; auto is probe-only. Test
/// seams: pass fake loaders. A backend whose loader returns null just isn't in
/// `available`, so the resolver falls to the next runtime (or pure-Dart).
Future<TranscriptionEngines> resolveEngines(
  TranscriptionEngineConfig config, {
  bool isWeb = kIsWeb,
  // onnx (pure-Dart) loaders — the live path.
  Future<NeuralTranscriber?> Function({bool download}) loadNeural =
      loadNeuralTranscriber,
  Future<F0Estimator?> Function({bool download}) loadRmvpe =
      loadRmvpeF0Estimator,
  Future<F0Estimator?> Function({bool download}) loadCrepeOnnx =
      loadCrepeF0Estimator,
  Future<ChordEstimator?> Function({bool download}) loadHarmony =
      loadHarmonyEstimator,
  // onnxFfi (native ONNX Runtime) loaders — stubs until a binding lands.
  Future<F0Estimator?> Function({bool download}) loadF0OnnxFfi = loadOnnxFfiF0,
  Future<NeuralTranscriber?> Function({bool download}) loadNeuralOnnxFfi =
      loadOnnxFfiNeural,
  Future<ChordEstimator?> Function({bool download}) loadChordsOnnxFfi =
      loadOnnxFfiChords,
  // crispasr (ggml) loaders — stubs until the pub package ships.
  Future<F0Estimator?> Function({bool download}) loadCrepeGgml =
      loadCrispasrCrepeF0,
  Future<NeuralTranscriber?> Function({bool download}) loadPianoGgml =
      loadCrispasrPiano,
}) async {
  final f0Explicit = config.backendFor(TranscriptionStep.f0) != Backend.auto;
  final polyExplicit =
      config.backendFor(TranscriptionStep.polyphonic) != Backend.auto;
  final chordsExplicit =
      config.backendFor(TranscriptionStep.chords) != Backend.auto;

  // Probe every runtime for every step. RMVPE is preferred over CREPE within the
  // pure-Dart ONNX runtime; the FFI runtimes are single-model (stubs today).
  final onnxF0 = await loadRmvpe(download: f0Explicit) ??
      await loadCrepeOnnx(download: f0Explicit);
  final ffiF0 = await loadF0OnnxFfi(download: f0Explicit);
  final ggmlF0 = await loadCrepeGgml(download: f0Explicit);

  final onnxNeural = await loadNeural(download: polyExplicit);
  final ffiNeural = await loadNeuralOnnxFfi(download: polyExplicit);
  final ggmlNeural = await loadPianoGgml(download: polyExplicit);

  final onnxChords = await loadHarmony(download: chordsExplicit);
  final ffiChords = await loadChordsOnnxFfi(download: chordsExplicit);

  final f0 = config.resolve(
    TranscriptionStep.f0,
    isWeb: isWeb,
    available: {
      if (ggmlF0 != null) Backend.crispasr,
      if (ffiF0 != null) Backend.onnxFfi,
      if (onnxF0 != null) Backend.onnx,
    },
  );
  final poly = config.resolve(
    TranscriptionStep.polyphonic,
    isWeb: isWeb,
    available: {
      if (ggmlNeural != null) Backend.crispasr,
      if (ffiNeural != null) Backend.onnxFfi,
      if (onnxNeural != null) Backend.onnx,
    },
  );
  final chords = config.resolve(
    TranscriptionStep.chords,
    isWeb: isWeb,
    available: {
      if (ffiChords != null) Backend.onnxFfi,
      if (onnxChords != null) Backend.onnx,
    },
  );

  return (
    f0: switch (f0.backend) {
      Backend.crispasr => ggmlF0,
      Backend.onnxFfi => ffiF0,
      Backend.onnx => onnxF0,
      _ => null,
    },
    neural: switch (poly.backend) {
      Backend.crispasr => ggmlNeural,
      Backend.onnxFfi => ffiNeural,
      Backend.onnx => onnxNeural,
      _ => null,
    },
    chords: switch (chords.backend) {
      Backend.onnxFfi => ffiChords,
      Backend.onnx => onnxChords,
      _ => null,
    },
  );
}
