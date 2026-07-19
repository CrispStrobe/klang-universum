// Native provider: load the CREPE ONNX model (download-on-demand) and wrap it
// as an F0Estimator the monophonic chain can use instead of pYIN. dart:io only —
// reached solely through crepe_provider.dart's conditional import, so web never
// compiles it.

import 'package:comet_beat/core/audio/transcription/crepe_model_store.dart';
import 'package:comet_beat/core/audio/transcription/route.dart'
    show F0Estimator;

/// A CREPE-backed [F0Estimator], or null.
///
/// With [download] false, returns non-null only if the model is already cached
/// (no network touched). With [download] true, fetches it first. Returns null on
/// any failure so the caller can fall back to the pure-Dart pYIN chain.
Future<F0Estimator?> loadCrepeF0Estimator({bool download = false}) async {
  try {
    if (!download && !crepeModelPresent()) return null;
    // crepeF0Estimator loads the model (downloading if missing) and reads the
    // env for any isolate-pool config; defaults to the single-threaded path.
    return await crepeF0Estimator();
  } on Object {
    return null;
  }
}

/// Whether the CREPE model is already on disk (a large-enough file), without
/// touching the network — the "is neural pitch ready?" gate for the UI.
bool crepeModelPresent() {
  try {
    final f = CrepeModelStore().modelFile();
    return f.existsSync() && f.lengthSync() > 500000;
  } on Object {
    return false;
  }
}
