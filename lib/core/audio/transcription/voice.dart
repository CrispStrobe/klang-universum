// lib/core/audio/transcription/voice.dart
//
// Seams for the singing-VOICE-conversion stack (RVC / w-okada ecosystem), kept
// SEPARATE from the frozen transcription `contracts.dart`. An SVC pipeline is
//   content-encoder → (+ F0 + speaker) → generator/vocoder → audio.
// The F0 half already exists (RMVPE/CREPE/FCPE via the `F0Estimator` seam); this
// file adds the two new seams the voice-conversion half needs. Pure data,
// Flutter-free, additive — nothing here touches the transcription contracts.
library;

import 'dart:typed_data';

/// The output of a content encoder (HuBERT / ContentVec): per-frame content
/// features [feats] laid out row-major `[frames × dim]` (`feats[t*dim + c]`),
/// at the encoder's own frame rate (HuBERT: 50 fps for 16 kHz audio, i.e. one
/// frame per 320 samples). [dim] is 256 (vec-256-layer-9) or 768
/// (vec-768-layer-12).
typedef ContentFeatures = ({Float32List feats, int frames, int dim});

/// A content encoder (HuBERT/ContentVec), injected so callers never depend on
/// the native ONNX engine. Takes mono audio at [sampleRate] (resampled to
/// 16 kHz internally) → content features. The linchpin every SVC model shares.
typedef ContentEncoder = Future<ContentFeatures> Function(
  Float64List mono,
  int sampleRate,
);

/// A voice converter: content [features] + a per-frame F0 track ([f0Hz], one Hz
/// value per feature frame, 0 = unvoiced) + a target [speakerId] → converted
/// mono audio at [outSampleRate]. The heavy real-time HiFi-GAN implementations
/// live on the native (CrispASR) path; a lightweight DDSP-SVC implementation is
/// the pure-Dart / web fallback.
typedef VoiceConverter = Future<({Float64List audio, int sampleRate})> Function(
  ContentFeatures features,
  Float32List f0Hz,
  int speakerId,
);
