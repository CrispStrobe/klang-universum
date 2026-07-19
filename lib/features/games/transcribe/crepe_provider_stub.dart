// Web / no-dart:io fallback: there is no CREPE ONNX, so the monophonic chain
// uses the pure-Dart pYIN pitch tracker. Signature must match
// crepe_provider_io.dart.

import 'package:comet_beat/core/audio/transcription/route.dart'
    show F0Estimator;

/// Always null on web — no ONNX. [download] is accepted for a matching signature.
Future<F0Estimator?> loadCrepeF0Estimator({bool download = false}) async =>
    null;

/// The model is never present on web.
bool crepeModelPresent() => false;
