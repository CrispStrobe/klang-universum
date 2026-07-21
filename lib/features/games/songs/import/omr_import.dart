// Optical Music Recognition import — photograph/scan sheet music → a Score.
//
// Facade over a native FFI implementation (`_io`, via the crispembed ggml
// engine) and a web stub (`_stub`, always unavailable). The token→Score parse
// is pure-Dart in crisp_notation_core; only the recognition needs the native
// lib + a GGUF model, so web / a build without the lib degrade to `available:
// false` and the import UI hides the entry.
export 'omr_import_stub.dart' if (dart.library.io) 'omr_import_io.dart';
