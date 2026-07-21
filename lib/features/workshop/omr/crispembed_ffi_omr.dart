// Facade for the native CrispEmbed OMR engine (sheet-music image → `bekern`
// tokens via a Sheet Music Transformer GGUF) behind a conditional import so web
// / no-dart:io still compile. Raw dart:ffi against libcrispembed's
// `crispembed_ocr_model_*` C ABI. Fills crisp_notation's OmrEngine seam; a
// pure-Dart-ONNX engine can drop in behind the same seam later (#4).

export 'crispembed_ffi_omr_stub.dart'
    if (dart.library.io) 'crispembed_ffi_omr_io.dart';
