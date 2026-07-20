// Facade for the CrispASR CREPE F0 estimator via the `crispasr` package's own
// Dart FFI (CrispasrSession.pitch), behind a conditional import so web / no
// dart:io still compile. This is the PRODUCTION native ggml path — an in-app
// FFI call, no shell-out — that the CLI provider (crispasr_pitch.dart) was a
// placeholder for. crispasr 0.8.16+ exposes `pitch(Float32List pcm16k)` whose
// PitchFrame record is field-for-field ours, so no adapter is needed.

export 'crispasr_ffi_pitch_stub.dart'
    if (dart.library.io) 'crispasr_ffi_pitch_io.dart';
