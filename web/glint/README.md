# glint Vorbis wasm (web `.sf3` decoder)

The MIT [glint](https://github.com/CrispStrobe/glint) Ogg-Vorbis decoder,
emscripten-built, for decoding compressed `.sf3` SoundFonts on the **web** target
(native uses the `native/glint` FFI plugin instead).

- `glint.wasm` / `glint.mjs` — the emscripten module (built in glint's
  `bindings/wasm`; re-copy after a glint wasm rebuild).
- `glint_codec.mjs` — glint's high-level API (`decodeVorbis`, `decodeAudio`).
- `glint_vorbis_web.js` — a SYNCHRONOUS decode shim (pre-load once, then decode
  per stream synchronously — fits `Sf2SoundFont.parse`'s sync `VorbisDecode`).
  Verified in node: byte-identical to the async path.
- `bootstrap.js` — loaded by `web/index.html`; exposes `globalThis.glintVorbis`
  for `lib/core/audio/sf2/vorbis_capability_web.dart`.

Loaded lazily (only on the first `.sf3`), so no startup cost.
