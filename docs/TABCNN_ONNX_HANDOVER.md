# TabCNN → ONNX — worker handover (onnx_runtime_dart agent)

**Mission:** publish a `tabcnn.onnx` (+ its CQT filterbank blob) that runs on the
**pure-Dart `onnx_runtime_dart`** and emits the frozen audio→tab contract, so
CometBeat's already-shipped decoder can turn a guitar recording into editable
tablature. You own **the model + the CQT spec + parity + the published asset.**
CometBeat owns the DP and the app wiring.

This is the **audio arm** of the tab work. The decision to adopt it is CrispASR's
scoping pass `CrispASR/docs/music-transcription/GUITAR_TAB_SPEC.md` §GT1; the
caller-side contract + Viterbi decoder already exist in CometBeat
(`lib/features/games/composition/tab_emission_decoder.dart`,
`docs/TAB_ARRANGER_NEURAL_HANDOFF.md`). Nothing below changes those — you produce
the emissions they already know how to consume.

---

## 0. ⛔ HARD GATE — do this FIRST, it can kill the task

**Verify the training-data licence before any conversion.** GuitarSet trains
*every* audio-arm candidate; if it forbids commercial use of derived weights, the
whole arm dies and you ship nothing.

- **GuitarSet** licence — the base corpus. UNVERIFIED in the scoping pass.
- **GP-FX augmentation** (DAFx-24) — the variant we actually want; confirm
  its released weights + the re-rendered audio are redistributable.
- **EGSet12** (Zenodo 11406378) — needed only as an acceptance set, but check it.

If any forbids redistribution of derived weights, STOP and report — do not publish
an unlicensable asset (this is the DadaGP mistake from §2.3 of the spec: an
`--accept-license` tag cannot launder an unlicensed corpus). A nameable
permissive/`NC` licence we can tag is fine; *no* licence is not.

---

## 1. Which weights

Ship the **GP-FX-augmented TabCNN**, not the vanilla one — vanilla's
GuitarSet tablature-F1 0.748 collapses to **0.447 zero-shot on real electric
guitar** (EGSet12); re-rendering the training audio with real tones lifts it to
**0.585** (architecture/optimizer/LR/data-split all held constant).

- TabCNN (Wiggins & Kim, ISMIR 2019): <https://github.com/andywiggins/tab-cnn>
  (Keras/TF) — the architecture + the fallback if the augmented weights aren't
  cleanly licensed.
- GP-FX variant (DAFx-24, Pedroza et al.):
  <https://dafx.de/paper-archive/2024/papers/DAFx24_paper_99.pdf> ·
  <https://arxiv.org/html/2405.14679>
- ⚠ Do **not** substitute FretNet without telling CometBeat — its tab head is
  **not** a per-string softmax, so the decoder's class layout wouldn't match.

~0.8 M params, comfortably small.

## 2. The frozen emission contract (match it exactly)

From `tab_emission_decoder.dart` — the ABI the decoder consumes:

- **Output = log-probabilities** (`LogSoftmax` over the 21 classes **per
  string**), NOT softmax and NOT raw logits. The DP sums costs and must never
  take `log(0)`; the original model ends in softmax, so **append a per-string
  `LogSoftmax` to the exported graph** (or replace the softmax with it).
- **Shape:** the original TabCNN is a single-window classifier. Export it that
  way — input one CQT context window, output `[6, 21]` (6 strings × 21 classes).
  Support a batch dim so CometBeat can push `N` windows at once → `[N, 6, 21]`.
  CometBeat slides one window per audio frame, so `N == T` and it assembles the
  `[T, 6, 21]` `TabEmissionFrames` itself.
- **Class layout (do not reorder):** class `0` = string **silent** ("closed" / not
  played); class `k ≥ 1` = **fret `k−1`** (class 1 = open, class 20 = fret 19).
  21 classes, 6 strings.
- **Input window:** TabCNN's `9 × 192 × 1` — a 9-frame context of 192 CQT bins,
  1 channel. State the exact tensor **names + dtype + axis order** you export
  (e.g. `input: float32[N,9,192,1]`, `output: float32[N,6,21]`); CometBeat pins
  them.
- Alongside the model you must state the **frame hop in seconds** (from the CQT
  hop ÷ sample rate) — the decoder needs it to place notes on a time grid.

## 3. Conversion + runtime op coverage

- Keras/TF → ONNX via `tf2onnx`. Keep it the original network; the only graph
  edit is the `LogSoftmax` head.
- **`onnx_runtime_dart` already implements every op TabCNN needs** — Conv,
  MaxPool, AveragePool, Relu, Flatten/Reshape, Gemm/MatMul, Transpose, and
  **LogSoftmax**. Verify the exported graph uses only supported ops: load it in
  the runtime and run one window. If `tf2onnx` emits a fused/unsupported variant
  (a fused Conv-BN, a `Dropout` left in, an odd `Squeeze`), either constant-fold
  it out at export or add the op to the runtime — this is your repo, so a missing
  op is fixable here rather than blocking CometBeat.
- Precedent: BTC (chords) and Basic Pitch already run CQT→ONNX purely in Dart on
  this runtime — TabCNN is smaller and shape-simpler.

## 4. ⚠ THE CQT front-end is the #1 correctness risk

TabCNN is trained on a **specific** `librosa.cqt` preprocessing; get it wrong and
the model reads garbage while every cheap check still passes.

- **Document TabCNN's exact CQT:** sample rate, hop, `n_bins = 192`,
  `bins_per_octave`, `fmin`, and **the per-frame normalization the repo applies**
  (TabCNN normalizes each frame — reproduce it precisely).
- **Ship a precomputed filterbank blob** in CometBeat's `harmony_cqt.dart`
  `CqtFilterBank` binary format (int32 header + lengths + lo/hi/offset + re/im
  bands — see the loader in that file), generated at 192 bins to match librosa,
  so the Dart front-end is bit-parity with training. (CometBeat already runs this
  exact filterbank format for BTC at 144 bins.)
- **Assert on magnitude, not just shape.** The BTC lesson: `core/cqt.h` shipped a
  **152× scale bug** that cosine similarity and peak-bin match could not see
  because both are scale-invariant. Your CQT parity check MUST assert the **median
  per-bin magnitude ratio ≈ 1**, not only correlation.

## 5. Parity harness (mirror the CREPE/BTC precedent)

`tools/tabcnn_parity.py` — against the Keras reference on GuitarSet clips:
1. **CQT front-end:** Dart `CqtFilterBank(192)` vs `librosa.cqt` → cosine **and**
   median magnitude ratio.
2. **Model output:** `onnx_runtime_dart` `[6,21]` log-probs vs the reference
   (exp'd back to probs for comparison) → per-string argmax agreement + KL.
3. **End-to-end round-trip:** run onnx → `[T,6,21]` → CometBeat's
   `decodeTabEmissions()` on a known monophonic clip; assert the decoded frets
   match the played notes. (A reference dump with no consumer is dead code that
   looks like coverage — wire both halves.)

## 6. Publish (same shape as crepe-tiny.onnx)

- Upload `tabcnn.onnx` **and** the CQT filterbank blob as **`models-v1` release
  assets** on `CrispStrobe/onnx_runtime_dart` (crepe-tiny.onnx lives there:
  `.../releases/download/models-v1/crepe-tiny.onnx`).
- Give CometBeat the **asset URLs + sha256** so a `TabCnnModelStore` can pin +
  cache them (mirroring `crepe_model_store.dart`: download-on-first-use,
  `COMET_TABCNN_DIR` override, null-on-offline).
- Registry entry with a **`license` field** naming the corpus provenance (§0). If
  it can't be named, it doesn't ship.

## 7. Acceptance (bytes are NOT the target — tab is a preference)

- Playability invariants hold structurally (the decoder enforces them) — not your
  concern; your number is emission quality.
- **Report EGSet12 zero-shot F1 alongside GuitarSet**, and lead with it. GuitarSet
  6-fold is the *training* protocol, so it flatters; EGSet12 is what predicts real
  behaviour (spec §7). Don't quote the GP-FX gain magnitude as precise
  (σ 0.06–0.11, only tablature-F1 clears p<0.05).

## 8. Deliverables checklist

- [ ] §0 licence cleared + named, or a STOP report.
- [ ] `tabcnn.onnx` — single-window classifier, per-string `LogSoftmax` head,
      only onnx_runtime_dart-supported ops, verified to run.
- [ ] CQT filterbank blob (192 bins) in `CqtFilterBank` format + a written spec of
      the exact librosa params + per-frame normalization.
- [ ] `tools/tabcnn_parity.py` — CQT (cos + **magnitude ratio**), model output,
      and the end-to-end `decodeTabEmissions` round-trip.
- [ ] `models-v1` release assets + URLs + sha256 + licence tag handed to CometBeat.
- [ ] EGSet12 zero-shot + GuitarSet numbers reported.

CometBeat then writes the small pure-Dart provider (a `TabCnnModelStore` +
`CqtFilterBank` front-end implementing `TabEmissionModel`) — a follow-up mirroring
`crepe_model_store` + the harmony CQT usage. Offer to do it too if you're touching
CometBeat; otherwise it's a clean CometBeat-side task once the asset lands.

## Coordination

Standard: feature branch + a git worktree; verify with the repo's own build/test;
no PRs, merge to `main`; report the asset URLs + CQT spec back to the CometBeat
`docs/TAB_ARRANGER_NEURAL_HANDOFF.md` §audio section when done so the provider has
a pinned target.
