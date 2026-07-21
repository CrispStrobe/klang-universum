// Facade for the native CrispASR TabCNN emitter (audio → tab emissions via ggml)
// behind a conditional import so web / no-dart:io still compile. Raw dart:ffi
// against libcrispasr's `crispasr_session_tab*` C ABI (crispasr v0.8.18) — no
// dependency on a Dart `.tab()` wrapper. Fills the same TabEmissionModel seam as
// the pure-Dart-onnx TabCnnEmitter; the resolver prefers this when the native
// lib + GGUF are present, else falls back to onnx.

export 'crispasr_ffi_tab_stub.dart'
    if (dart.library.io) 'crispasr_ffi_tab_io.dart';
