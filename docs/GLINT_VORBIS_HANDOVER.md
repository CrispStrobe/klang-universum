# Handover: add an Ogg-Vorbis I DECODER to glint (for `.sf3` soundfonts)

**Audience:** an autonomous agent (Opus-class) working in the **glint** repo
(`~/code/glint`). **Driver:** CometBeat's SoundFont reader needs to decode `.sf3`
soundfonts, whose samples are **Ogg Vorbis**; glint today decodes MP3 / AAC-LC /
Opus but has **no Vorbis** codec. This handover defines exactly what to build,
the contracts, the test harness, and the condition of done.

Read `~/code/glint/README.md`, `CLAUDE.md` and `PLAN.md` first — match glint's
existing conventions exactly (clean-room, MIT, spec-derived tables, decode-vs-
reference dB gates, ASan+UBSan fuzz, ctest, an experiment log in `PLAN.md`).

---

## 1. Goal (one sentence)

Add a **clean-room Ogg-Vorbis I decoder** to glint — from the Vorbis I spec
only — that decodes an Ogg-Vorbis logical stream to PCM, wired into glint's
whole-file `glint_decode_audio` auto-detect and exposed through the C ABI +
Dart (FFI) + wasm (+ Python/Rust) bindings, verified against ffmpeg and a second
reference at glint's usual dB bar and fuzz-hardened.

**Non-goals:** a Vorbis *encoder*; Vorbis II; chained/multiplexed multi-stream
Ogg beyond what `.sf3` needs (single logical stream per sample is the case).
Deliver the DECODER.

## 2. Why this is a good fit for glint (leverage, don't reinvent)

- glint already has the **Ogg framing** (page/packet reassembly) for Ogg-Opus
  (`src/opus_ogg.hpp`) — factor it so Vorbis reuses it.
- glint already has **MDCT** infrastructure (`src/opus_mdct.hpp`,
  `src/aac_mdct.*`) and even references the **Vorbis power window** in comments
  (`src/opus_celt_tables.hpp:55`, `src/opus_mdct.hpp:103`). Vorbis' inverse MDCT
  + windowed overlap-add can build on this.
- What's genuinely new is the **Vorbis codec body**: codebooks (Huffman +
  vector-quantized), floor (types 0 LSP and 1 piecewise-linear), residue (types
  0/1/2) with inverse channel coupling, and the mapping/setup header parse.

## 3. Scope of the decode pipeline (Vorbis I spec §4–§9, §12)

1. **Ogg demux** (reuse): extract the logical Vorbis bitstream's packets.
2. **Three header packets:** identification (§4.2.2 — channels, sample rate,
   blocksizes), comment (skip contents), **setup** (§4.2.4 — codebooks, floors,
   residues, mappings, modes). This is the bulk of the parse work.
3. **Audio packet decode** (§4.3): mode → blocksize + window; per-channel floor
   decode; residue decode; **inverse coupling** (angle/magnitude); dot-product
   floor × residue; **inverse MDCT**; **windowed overlap-add** across packets
   (long/short block transitions).
4. Output: interleaved PCM (float ±1.0, and an int16 path for `_ex`), at the
   stream's native rate, mono or stereo (support ≥ the channel counts `.sf3`
   uses — mono is the common case; do stereo too for general `.ogg`).

Sub-decoders to implement + unit-test in isolation: codebook (scalar +
VQ lookup types 1/2), floor 1 curve synthesis, floor 0 (LSP), residue 0/1/2.

## 4. Clean-room constraint (hard)

Implement from the **Vorbis I specification** (xiph.org) only. Do **not** read or
copy libvorbis / stb_vorbis / ffmpeg / tremor source. Derive any tables from the
spec text; document provenance like glint does for its AAC tables. Add a
one-line clean-room affidavit to `PLAN.md` and MIT headers on new files. (ffmpeg
/ libvorbis are allowed **only** as black-box *reference decoders* in tests.)

## 5. Contracts — C ABI (`include/glint/glint.h`)

Match glint's existing per-codec + whole-file style. Add:

```c
// --- Vorbis decoder (Ogg-Vorbis I) ---
typedef struct glint_vorbis_dec_context* glint_vorbis_dec_t;

// Decode a COMPLETE in-memory Ogg-Vorbis logical stream (headers + audio) to
// interleaved float PCM (+-1.0). This whole-buffer form fits .sf3, where each
// sample is its own short Ogg stream. Returns a malloc'd buffer of
// out_frames*out_ch floats (free with glint_free), writes sample rate, channel
// count and per-channel frame count. NULL on error / not-Vorbis.
float* glint_vorbis_decode(const uint8_t* ogg, int len,
                           int* out_sr, int* out_ch, int* out_frames);

// int16 + optional resample sibling, mirroring glint_decode_audio_ex.
void*  glint_vorbis_decode_ex(const uint8_t* ogg, int len, int out_rate,
                              int want_int16, int* out_sr, int* out_ch,
                              int* out_frames);
```

**Also update `src/decode_audio_c_api.cpp`** — its `detect()` currently maps ANY
`OggS` to `Fmt::Opus`. Distinguish by the first Ogg packet's codec-identification
header: `OpusHead` → Opus, `\x01vorbis` (0x01 + "vorbis") → **Vorbis**. Add
`Fmt::Vorbis` and route it to the new decoder. `glint_decode_audio` /
`glint_decode_audio_ex` must then transparently decode Ogg-Vorbis with **no
regression** to Opus/MP3/AAC.

(If a streaming/packet API is also wanted for symmetry, add
`glint_vorbis_dec_create/decode/destroy` like the Opus one — optional; the
whole-buffer form above is what the `.sf3` integration needs.)

## 6. Contracts — bindings (parity with existing codecs)

- **Dart** (`bindings/dart/lib/glint_audio.dart`, FFI): a `GlintVorbisDecoder`
  (or extend the whole-file decode helper) exposing
  `({int sampleRate, int channels, Float32List pcm}) decode(Uint8List ogg)` and
  an int16 variant, wired via `lookupFunction` like `GlintOpusDecoder`. The
  existing whole-file Dart decode path should also transparently accept Vorbis
  once the C detect is fixed.
- **wasm** (`bindings/wasm/glint_codec.mjs`): `decodeAudio(bytes)` already calls
  `_glint_decode_audio`, so it works for Vorbis after the C detect fix — add
  `FORMAT.VORBIS` and a smoke path; ensure the emscripten export list
  (`bindings/wasm/build.sh`) includes any new symbols. **Web is a first-class
  target** — a Vorbis `.ogg` must decode through the wasm build.
- **Python/Rust**: add parity wrappers matching the existing decoders (glint
  keeps all four bindings in lockstep).

## 7. Testing harness (match glint's methodology exactly)

glint's bar: decode-vs-reference SNR in dB, two independent references, fuzz
under sanitizers, ctest gates, a Python driver. Mirror it:

1. **`tools/test_vorbis_decoder.py` + ctest `vorbis_decoder_vs_ffmpeg`** —
   decode a corpus of Ogg-Vorbis files with glint and with **ffmpeg**
   (`ffmpeg -i x.ogg -f f32le -ac N -`), align and compute SNR. **Vorbis decode
   is deterministic**, so glint vs a correct reference decoder must be **very
   high** — gate at **≥ 120 dB** (float-rounding floor), not the lossy-encode
   bar. Corpus: generate with `oggenc`/`ffmpeg` at q0/q3/q6/q10, **mono and
   stereo**, short (<0.1 s, the `.sf3` case) and long clips, plus low/high
   sample rates (22.05 k is common in soundfonts).
2. **Second reference decoder:** also compare against **libvorbis** via
   `oggdec` (or `sox x.ogg -t f32 -`) at the same dB gate — glint must match
   *both*, exactly as the MP3/AAC gates check ffmpeg AND CoreAudio.
3. **`.sf3` end-to-end acceptance (the real driver):** fetch **FluidR3Mono.sf3**
   (MuseScore, MIT — `github.com/musescore/MuseScore/.../FluidR3Mono_GM.sf3`).
   Its `smpl` chunk holds concatenated Ogg-Vorbis streams (each begins `OggS`
   … `\x01vorbis`). For a sample of GM presets: pass each sample's Ogg stream to
   `glint_vorbis_decode`, and (a) SNR-compare vs ffmpeg decoding the same
   extracted stream (≥ 120 dB); (b) a **musical** check — the decoded piano/
   organ/flute samples, played at their root key, read on-pitch (reuse a pitch
   detector; a clean organ tone should be within a few cents). Document counts.
4. **Fuzz:** extend `tools/fuzz_decoders.cpp` (ctest `decoder_fuzz`) with a
   Vorbis target — random / truncated / bit-flipped Ogg-Vorbis under **ASan +
   UBSan**: no crash, no OOB, no hang, bounded allocation. Match the
   ≥~1M-iteration bar the other decoders meet. Include malformed setup headers
   (huge codebook dims, bad floor/residue params) — the classic Vorbis attack
   surface.
5. **Unit tests** (`tests/test_unit.cpp`): codebook VQ lookup (types 1/2 against
   hand-worked spec examples), floor 1 curve synthesis on a known control set,
   residue partition decode, and the id-header parse (blocksizes power-of-two,
   rate/channels sane).

## 8. Condition of Done (all must hold)

1. glint decodes arbitrary **Ogg-Vorbis I** streams to PCM, matching **ffmpeg
   AND libvorbis at ≥ 120 dB SNR** across the corpus (mono+stereo, q0…q10,
   22.05/44.1 k, short+long).
2. `glint_decode_audio`/`_ex` **auto-detect Vorbis vs Opus** (both `OggS`) via
   the codec-id header, with **zero regression** on the existing MP3/AAC/Opus
   decode gates (run the full existing ctest suite — all still green).
3. **C ABI + Dart + wasm + Python + Rust** bindings expose Vorbis decode;
   `decodeAudio(bytes)` on the **wasm/web** path decodes a Vorbis `.ogg`.
4. **Fuzz-clean** under ASan+UBSan at glint's iteration bar (ctest
   `decoder_fuzz`), including malformed setup headers.
5. **Real `.sf3` end-to-end:** FluidR3Mono.sf3 samples decode via glint,
   SNR-match ffmpeg (≥120 dB) on ≥20 sampled presets, and a decoded organ/flute
   voice reads on-pitch (± a few cents).
6. New ctest gates added and passing (`vorbis_decoder_vs_ffmpeg`, fuzz);
   `PLAN.md` experiment log + clean-room affidavit updated; MIT headers on new
   files; no third-party codec source referenced.

## 9. Integration contract (CometBeat side — the follow-up, NOT this agent's job)

Once glint ships the above, CometBeat's `lib/core/audio/sf2/sf2.dart` will drop
its `.sf3`-reject path and instead: for each shdr whose sample region is an
Ogg-Vorbis stream (detected today by the `OggS` magic via `sf2IsCompressed`),
hand that byte range to glint's whole-buffer `glint_vorbis_decode` → PCM →
`Sf2Sample`. So the **only surface CometBeat depends on** is:

> **decode one complete Ogg-Vorbis byte buffer → (Float32/Int16 PCM, sampleRate,
> channels).** Mono, short streams, native rate. Keep that API stable.

Native uses glint via `dart:ffi`; web uses the glint **wasm** build (so the sf2
`.sf3` path must be behind a platform seam). glint must therefore ship both a
loadable native lib and the wasm module for the Dart/JS bindings.

## 10. Environment / build notes

- Build: CMake (`~/code/glint/CMakeLists.txt`) → `ctest`. wasm via emsdk
  (`bindings/wasm/build.sh`; `~/code/emsdk` exists).
- Keep commits small and spec-section-scoped (id-header → setup/codebooks →
  floor → residue → mapping/imdct → Ogg glue → detect+ABI → bindings → fuzz),
  each with its ctest passing, mirroring how glint's other codecs were staged.
- Report progress in `PLAN.md` with measured dB numbers per corpus clip, as the
  existing codecs do.

**Definition of "done" in one line:** `ffmpeg`, `libvorbis` and `glint` all
decode the same Ogg-Vorbis streams to within 120 dB; a real FluidR3Mono.sf3
plays in tune through glint on both native and web; fuzz-clean; existing gates
unregressed.
