// Web / no-dart:io fallback: no CrispASR FFI. Matches the IO signature.

import 'package:comet_beat/core/audio/transcription/route.dart'
    show NeuralTranscriber;

Future<NeuralTranscriber?> loadCrispasrPianoFfi({bool download = false}) async {
  return null;
}
