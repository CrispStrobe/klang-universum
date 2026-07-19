// CREPE F0-estimator provider for the Transcribe screen, behind a conditional
// import so the screen compiles on web. The IO implementation loads the CREPE
// ONNX model (pulls dart:io) and wraps it as an F0Estimator the monophonic
// chain can use in place of pYIN; the stub returns null (web) so the chain
// falls back to the pure-Dart pYIN pitch tracker.
//
// `loadCrepeF0Estimator({download})`:
//   • download == false → return an estimator only if the model is ALREADY on
//     disk (no network); else null.
//   • download == true  → fetch the model if missing, then return an estimator
//     (returns null on any failure so the caller can fall back to pYIN).

export 'crepe_provider_stub.dart' if (dart.library.io) 'crepe_provider_io.dart';
