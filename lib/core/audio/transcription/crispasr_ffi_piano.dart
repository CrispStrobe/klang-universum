// Facade for CrispASR ggml PIANO transcription via the crispasr package FFI
// (CrispasrSession.pianoNotes, crispasr 0.8.17+). Behind a conditional import
// so web/no-dart:io still compile (null stub → resolver falls back to the
// pure-Dart onnx Basic Pitch). PianoNote maps straight onto our NoteEvent.

export 'crispasr_ffi_piano_stub.dart'
    if (dart.library.io) 'crispasr_ffi_piano_io.dart';
