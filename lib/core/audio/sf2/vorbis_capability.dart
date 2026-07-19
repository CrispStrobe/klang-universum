// Platform seam for the `.sf3` Ogg-Vorbis decoder. Mirrors
// core/audio/aec_capability.dart: the conditional export compiles the
// dart:ffi-backed glint decoder ONLY where dart:ffi exists (native), and a
// dart:ffi-free stub everywhere else (web) — so `.sf3` support can be requested
// from platform-agnostic code without breaking the web build.
//
// Use: `Sf2SoundFont.parse(bytes, vorbis: loadGlintVorbis())`. On native with
// the glint library available it decodes `.sf3`; otherwise it returns null and
// `.sf3` falls back to the clear "needs a Vorbis decoder" rejection. See
// docs/GLINT_VORBIS_HANDOVER.md.

// Native (dart:ffi) → the glint FFI plugin; web (dart:js_interop) → the glint
// wasm shim; neither → the null stub. `ffi` is checked first so native never
// falls into the web path.
export 'vorbis_capability_stub.dart'
    if (dart.library.ffi) 'vorbis_capability_ffi.dart'
    if (dart.library.js_interop) 'vorbis_capability_web.dart';
