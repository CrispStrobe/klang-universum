# TabCNN native ggml `--tab` — handback (CrispASR → CometBeat)

Answers the "Hand back: the session ABI signatures + the exact input tensor
layout you expect" line in `TABCNN_GGML_HANDOVER.md`.

**Status:** the C++ backend, the `--tab` CLI verb and the session C ABI are
landed and shipped (CrispASR v0.8.18). The GGUF is published at
`cstr/tabcnn-GGUF` and reachable via `-m auto`.

**One deliberate divergence from the frozen contract — read §2 before writing
the FFI provider.** It is an off-by-one that produces plausible-looking
tablature rather than an error, so it will not announce itself.

---

## 1. Session ABI

From `include/crispasr_session.h`. Open the session with
`crispasr_session_open_explicit(model_path, "tabcnn", n_threads)`.

```c
// Runs the model. Returns the frame count, or <0 on bad arguments.
int   crispasr_session_tab(crispasr_session* s, const float* pcm,
                           int n_samples, int sample_rate);

int   crispasr_session_tab_n_frames(crispasr_session* s);

// Flat [frame][string][class] LOG-probabilities, row-major.
// Valid until the next call or session close — copy before reusing the session.
const float* crispasr_session_tab_emissions(crispasr_session* s,
                                            int* out_n_frames,
                                            int* out_n_strings,
                                            int* out_n_classes);

int   crispasr_session_tab_silent_class(crispasr_session* s);   // see §2
float crispasr_session_tab_frame_period(crispasr_session* s);   // 512/22050
int   crispasr_session_tab_string_open_midi(crispasr_session* s, int string);
```

Notes:

- **All-float view, as requested.** Every accessor returns `int`/`float`
  separately; the emission grid is pure `float`. Nothing mixes int and float
  lanes in one buffer.
- Indexing matches your `TabEmissionFrames.at()` exactly:
  `logProbs[(frame * 6 + string) * 21 + cls]`.
- Rows are `log_softmax` per `(frame, string)` — verified in
  `tests/test_tabcnn_live.cpp` (`|sum(exp(row)) - 1| < 1e-3`), not assumed.
- `string_open_midi` is read from the GGUF, not invented: standard tuning
  `40 45 50 55 59 64`. It returns `-1` out of range rather than reading past
  the array.
- Input is 16 kHz-agnostic — pass any `sample_rate`, the backend resamples to
  the model's 22050.

## 2. ⚠ Class layout — the shipped GGUF does NOT match the frozen contract

The contract in both handovers, and hardcoded at `tab_emission_decoder.dart:72`:

> class `0` = silent; class `k ≥ 1` = fret `k−1`

**The shipped GGUF is the upstream native order.** Read directly from
`tabcnn-f16.gguf`:

```
tabcnn.num_classes  = 21
tabcnn.silent_class = 20
```

so `class 0..19 = frets 0..19`, `class 20 = silent`. The GGML handover states
the remap is "already done in the export"; the converter
(`models/convert-tabcnn-to-gguf.py`) does a straight name-map
(`dense.3.output_layer.* → head.*`) and preserves upstream order. The ONNX
export remaps; the GGUF export does not.

**Consequence if the current decoder consumes these frames unchanged:**

| GGUF class | decoder reads it as | truth |
|---|---|---|
| 0 | silent | fret 0 (open) — open strings disappear |
| 1–19 | frets 0–18 | **every fret off by one** |
| 20 | fret 19 | silent — silence becomes a high fret |

No exception, no warning. Just wrong tablature that looks reasonable.

### Agreed resolution: carry the class, don't freeze it

Rather than republish the public GGUF, `TabEmissionFrames` should carry the
silent class the way it already carries `hopSeconds` — model geometry travelling
with the data instead of living as a constant:

```dart
class TabEmissionFrames {
  TabEmissionFrames({
    required this.nFrames,
    required this.hopSeconds,
    required this.logProbs,
    required this.silentClass,   // NEW
  });
  final int silentClass;
}
```

Four changes on the CometBeat side:

1. add `silentClass` to `TabEmissionFrames`;
2. `tab_emission_decoder.dart:72` — replace the literal `0` with
   `frames.silentClass` (and any other place comparing a class to `0`);
3. the existing onnx `TabCnnEmitter` passes `silentClass: 0` (its export is
   remapped — unchanged behaviour);
4. the new `crispasr_ffi_tab.dart` passes
   `silentClass: crispasr_session_tab_silent_class(s)` — do not hardcode 20
   either; a future retrain could move it again.

Fret for a non-silent class `k` becomes:
`k < silentClass ? k : k - 1` — which reduces to the old `k - 1` when
`silentClass == 0`, so the onnx path is arithmetically untouched.

**If you would rather keep the layouts byte-identical**, say so and CrispASR
will remap in the converter and republish all quants instead. That is a
one-line change on our side; it flips meaning for anyone already consuming the
published GGUF, which is why it was not done unilaterally. Remapping is
index-order only — the EGSet12 numbers below stand either way.

## 3. Front-end / variant

The shipped GGUF is the **gpfx** variant, and the C++ front end implements its
normalization: `|CQT| / √length` → `amplitude_to_db(ref=max, top_db=80)` →
min-max to `[0,1]`. Geometry is read from the GGUF, never hardcoded:

```
sr 22050 · hop 512 · n_bins 192 · bins_per_octave 24 · fmin 32.703 Hz (C1)
frame width 9 · 6 strings · 21 classes
```

Getting `fmin` wrong is silent: an early build used E2@44100 and scored
F1 0.0008 while passing every shape and cosine check. The parity harness
therefore asserts **median per-bin magnitude ratio** alongside cosine, per the
handover's §1 warning — cosine alone is scale-blind and would have passed it.

## 3b. Fret ceiling — the model tops out at fret 19

`num_classes = 21` = one silent class + **20 fret classes, 0..19**. Your decoder
already derives this correctly (`kTabMaxFret = kTabClasses - 2`), and the
derivation is layout-agnostic, so it holds under either §2 resolution.

This is architectural, not a porting choice: TabCNN's head is 21-wide and
GuitarSet / EGSet12 annotate 0..19. Nothing above fret 19 can be emitted at any
quantization or on any variant. Raising it means a wider head, new training
annotations, and a retrain.

**This does not match the document model**, which validates frets against 0..24
(`tab_document.transposeBy`). A hand-authored or imported tab may legitimately
contain fret 22; a *transcribed* one never will.

With standard tuning (the ABI's `string_open_midi` = 40 45 50 55 59 64):

| string | open | max @ fret 19 |
|---|---|---|
| E2 | 40 | 59 |
| A2 | 45 | 64 |
| D3 | 50 | 69 |
| G3 | 55 | 74 |
| B3 | 59 | 78 |
| E4 | 64 | **83** |

Two consequences worth designing around:

1. **Pitch ceiling MIDI 83 (B5).** A 24-fret guitar reaches MIDI 88 (E6), so
   **MIDI 84–88 is unrepresentable** — no string expresses it at ≤ fret 19. Lead
   playing above the 19th fret on the top string is simply outside the model's
   range. Expect the emissions to put that energy somewhere plausible and wrong
   (a lower octave position, or silent), with no signal that it happened.
2. **MIDI 79–83 has no fallback position.** Those pitches exceed the B string's
   ceiling of 78, so they are reachable *only* on the top string. Everywhere
   else the DP can re-finger a mis-scored note to an equivalent position and
   still land the right pitch; in this band it cannot. Mis-scoring there is
   unrecoverable by the decoder.

For pitches that *are* reachable elsewhere, note the failure mode is benign-ish:
the model may pick a different (string, fret) with the same pitch — right notes,
different fingering. That is a tab-quality issue, not a wrong-notes issue, and
is exactly what your playability constraints exist to shape.

If transcribing material known to go high, capo/tuning metadata is the lever:
`string_open_midi` is read from the GGUF rather than assumed, so a retuned or
capoed model would shift the whole table — but the 20-fret span is fixed.

## 4. Accuracy

EGSet12 zero-shot tablature F1 **0.7732** (torch reference 0.7708 on the same
split). Quantization: `head.weight` must stay F16 — quantizing it costs
**5.8 F1 points**, and `crispasr-quantize` now preserves it for tabcnn.

## 5. Verification status — what is and isn't proven

Proven: per-stage parity vs `tools/reference_backends/tabcnn.py` through
`crispasr-diff tabcnn` (13 stages, registered with a C++ consumer, not a dumper
without a reader); log-softmax normalization; digital silence scores unplayed on
every string; EGSet12 F1 above.

**Not proven:** round-trip through your `decodeTabEmissions()` on a known clip
(handover acceptance item 3). That needs the FFI provider, which is your side —
and it is the check that would have caught §2 immediately, from the decoded
frets rather than from reading source. Worth doing first.

---

## CometBeat response (2026-07-21)

**§2 — DONE** (`b11dc96d`). `TabEmissionFrames.silentClass` added (default 0, so
the remapped onnx/gpfx path is arithmetically untouched); `decodeTabEmissions`
reads it, and the fret map is `k < silentClass ? k : k-1` as agreed. The
per-string Viterbi's silent-state handling is generalised too. +3 tests proving
the SAME class indices decode to different frets/silence under `silentClass` 0
vs 20 (open-string-vanish, silence→fret-19, and the off-by-one are all now
caught). We keep the layouts as-is — **no GGUF republish needed**; the decoder is
GGUF-ready. The `crispasr_ffi_tab` provider will pass
`silentClass: crispasr_session_tab_silent_class(s)`.

**§3b — noted, no change.** `kTabMaxFret = kTabClasses - 2 = 19` already, and
layout-agnostic. Transcribed tab is 0..19, well inside the document model's 0..24
— hand-authored/imported tab may still go higher, which is correct. The
MIDI 79–83 no-fallback / 84–88 unrepresentable bands are a model-range property
we'll surface in the transcribe UX if it matters, not a decoder bug.

**✅ FFI provider SHIPPED + acceptance item 3 VERIFIED** (`320e46c8`). We did
NOT need the Dart `.tab()` wrapper — the 0.8.18 `libcrispasr-macos-arm64` on the
CrispASR GH release has the `crispasr_session_tab*` symbols, so
`crispasr_ffi_tab_io.dart` binds them with **raw `dart:ffi`** directly (open a
`"tabcnn"` session, run, read emissions + `silent_class` + `frame_period`, close;
GGUF `cstr/tabcnn-GGUF` f16 downloaded/cached). Defensive null on any failure →
falls back to the onnx path; `audioToTab` now prefers native. **Round-trip run on
the real GGUF (Metal): G3 pluck → 65 frames, `silentClass 20`, decodes to G-string
fret 5 — the SAME fret the onnx/gpfx path gives, so §2 is confirmed correct.**
+gated test (skips without `COMET_CRISPASR_LIB`).

**⚠ Two dylib-delivery issues for CrispASR to fix** (packaging, not the ABI —
which is perfect):
1. **`@rpath` points at the CI build path** — `otool -l` shows
   `LC_RPATH = /Users/runner/work/CrispASR/CrispASR/build-libs/ggml/src`, so a
   downloaded `libcrispasr.0.8.18.dylib` can't find `@rpath/libggml.0.dylib` and
   `DynamicLibrary.open` fails. Dev workaround: flatten all dylibs into one dir,
   `install_name_tool -add_rpath @loader_path` on each, `codesign -s -`. **Ship
   with `@loader_path`-relative rpaths** (or bundle the ggml libs beside
   libcrispasr with matching install names) so it loads as delivered.
2. The tar lays the libs across `src/` + `ggml/src/` — a single flat lib dir
   (like the pitch delivery) would drop cleanly into the app's Frameworks.

Nice-to-have but optional: a `CrispasrSession.tab()` in the pub package would let
us drop the raw FFI, but it's not needed — the provider works as-is.
