// Neural-engine provider for the Transcribe screen, behind a conditional import
// so the screen compiles on web. The IO implementation loads the Basic Pitch
// ONNX model (pulls dart:io); the stub returns null (web) so the router falls
// back to the pure-Dart monophonic chain.
//
// `loadNeuralTranscriber({download})`:
//   • download == false → return a transcriber only if the model is ALREADY on
//     disk (no network); else null.
//   • download == true  → fetch the model if missing, then return a transcriber
//     (throws only if unobtainable — the caller handles it).

export 'neural_provider_stub.dart'
    if (dart.library.io) 'neural_provider_io.dart';
