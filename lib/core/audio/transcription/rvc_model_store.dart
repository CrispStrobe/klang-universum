// lib/core/audio/transcription/rvc_model_store.dart
//
// NATIVE provisioning for an RVC generator — the `dart:io` half kept OUT of the
// web-safe `rvc.dart`. RVC voice models are NC / per-model licensed and are NOT
// hosted here: the USER supplies the ONNX (their own trained/downloaded voice),
// and loading is LICENCE-GATED (like the BTC chord model) — the caller must
// accept responsibility for the voice model's terms before it loads.
library;

import 'dart:io';

import 'package:comet_beat/core/audio/transcription/model_license.dart';
import 'package:comet_beat/core/audio/transcription/rvc.dart';
import 'package:comet_beat/core/audio/transcription/voice.dart'
    show VoiceConverter;
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// Loads a USER-SUPPLIED RVC generator ONNX from a local path. Licence-gated:
/// call `acceptModelLicense(RvcModelStore.licenseSpdx)` (or set
/// `COMET_ACCEPT_LICENSES`) first, asserting rights to the voice model.
class RvcModelStore {
  RvcModelStore({required this.modelPath});

  /// Path to the user's RVC generator ONNX, or a directory holding `rvc.onnx`.
  final String modelPath;

  /// The acceptance tag — RVC voice models are user-responsibility (NC / varied).
  static const licenseSpdx = 'RVC-voice-model';

  /// Output sample rate of the generator (RVC v2 = 40 kHz; v1 = 32/48 kHz).
  int outSampleRate = 40000;

  OnnxModel? _cached;

  File modelFile() {
    final f = File(modelPath);
    if (f.existsSync() && !FileSystemEntity.isDirectorySync(modelPath)) {
      return f;
    }
    return File('$modelPath/rvc.onnx');
  }

  bool isPresent() {
    final f = modelFile();
    return f.existsSync() && f.lengthSync() > 1000000;
  }

  /// Loads (and memoises) the model. Throws [ModelLicenseNotAccepted] if the
  /// voice-model licence hasn't been accepted, or [StateError] if absent.
  Future<OnnxModel> load() async {
    requireModelLicense('RVC voice model', licenseSpdx);
    if (_cached != null) return _cached!;
    final file = modelFile();
    if (!file.existsSync()) {
      throw StateError('RVC model not found at ${file.path}. Supply your own '
          'RVC generator ONNX (COMET_RVC_MODEL / the modelPath).');
    }
    return _cached = OnnxModel.fromBytes(file.readAsBytesSync());
  }

  /// The [VoiceConverter] seam backed by this model (offline).
  Future<VoiceConverter> converter() async =>
      rvcConverter(await load(), outSampleRate: outSampleRate);
}
