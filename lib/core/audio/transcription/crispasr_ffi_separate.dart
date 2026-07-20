// Facade for CrispASR ggml source separation via the crispasr package FFI
// (CrispasrSession.separate, crispasr 0.8.17+). Behind a conditional import so
// web/no-dart:io still compile (null stub). The in-app replacement for the
// `--separate` CLI shell-out (crispasr_separate.dart).

export 'crispasr_ffi_separate_stub.dart'
    if (dart.library.io) 'crispasr_ffi_separate_io.dart';
