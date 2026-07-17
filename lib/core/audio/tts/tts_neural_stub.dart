// lib/core/audio/tts/tts_neural_stub.dart
//
// Web / io-less stub: no native neural TTS here. Returns null so TtsService uses
// the platform (flutter_tts) voice.

import 'dart:typed_data';

import 'package:comet_beat/core/services/tts_service.dart';

NeuralTts? createNeuralTts({
  required Future<void> Function(Uint8List wav) play,
  Future<void> Function()? stopPlayback,
}) =>
    null;
