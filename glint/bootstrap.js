// Loaded from web/index.html as a module. Imports the glint Vorbis wasm shim and
// exposes it on globalThis so Dart (dart:js_interop) can reach it. The wasm is
// fetched LAZILY on the first glintVorbisInit() call (not at app startup), so
// this adds no startup cost until a .sf3 SoundFont is actually loaded.
import { glintVorbisInit, glintVorbisReady, glintVorbisDecodeSync }
  from './glint_vorbis_web.js';
globalThis.glintVorbis = {
  init: glintVorbisInit,          // async → resolves when the wasm is ready
  ready: glintVorbisReady,        // bool
  decodeSync: glintVorbisDecodeSync, // (Uint8Array) → {pcm,channels,frames}|null
};
