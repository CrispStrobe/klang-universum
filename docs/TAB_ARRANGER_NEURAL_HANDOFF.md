# Neural guitar-tab arranger — CrispASR handoff / seam spec

**Status: SPEC (design only — no product code yet). The pure-Dart baseline is
SHIPPED and is the fallback.** This doc specs a data-driven arranger that would
slot *behind the same seam* as the shipped heuristic, for more human-like
fingering. It mirrors how the transcription (`contracts.dart`) and SVC
(`svc-voice-conversion-seam`) efforts split "the model" from "our decode".

## What already ships (the baseline this replaces the *scorer* of, not the seam)

`lib/features/games/composition/tab_arranger.dart` — `arrangeTab(columns,
tuning, {capo, maxFret, cost})` runs the Sayegh'89 optimum-path **Viterbi** over
per-column candidate frettings: transition cost = hand-position shift, local cost
= chord span + a small low-neck pull. Chords seat on distinct strings, unreachable
notes drop, open strings are free hand-teleports, capo-aware. It drives
`TabDocument.fromScore` (which also honours explicit `Score.tabVoicings`, i.e. a
GP/MusicXML import keeps its fingering) and the MelodyBridge tab pull. 8 unit
tests. **Pure Dart, patent-free, no asset, no network** — this is the guaranteed
floor and the offline/web path. The neural model must degrade to it.

## The idea: keep the Viterbi, swap the *cost*

The heuristic's weakness is the hand-authored cost. The strong, low-risk upgrade
is to keep our Viterbi as the **arbiter** (so output is always physically
playable — one note per string, in fret range, capo-correct) and let a model
supply the **emission scores** it optimises. The model never emits tab directly;
it scores candidate positions. That guarantees no model hallucinates an
unplayable shape, and it stays swappable.

### The seam (add to `tab_arranger.dart`, backward-compatible)

```dart
/// Scores candidate (string,fret) placements per column. CrispASR implements
/// this behind FFI/ONNX; null → arrangeTab falls back to its heuristic local
/// cost, so every caller keeps working with no model present.
abstract interface class TabPositionModel {
  /// For each input column, a score per candidate position (higher = more
  /// idiomatic). Columns/candidates align 1:1 with arrangeTab's own candidate
  /// enumeration. Return null for a column to defer it to the heuristic.
  List<Map<(int string, int fret), double>?>? score(
    List<List<int>> columns, Tuning tuning, {int capo, int maxFret});
}

// arrangeTab gains ONE optional param — signature/callers unchanged otherwise:
List<Fretting> arrangeTab(List<List<int>> columns, Tuning tuning, {
  int capo = 0, int maxFret = 20, TabArrangeCost cost = const TabArrangeCost(),
  TabPositionModel? model,  // <-- new; when present, its score replaces the
});                          //     local term (transition term stays ours)
```

Local term becomes `model.score()[i][cand] ?? heuristicLocal(cand)` (negated to a
cost). The transition term (hand movement) **stays ours** — it's a hard physical
prior the model shouldn't be trusted to relearn. The `List<List<int>> →
List<Fretting>` shape callers use is untouched.

## Audio arm — the caller side is BUILT (seam + decoder), awaiting weights

CrispASR's scoping (`docs/music-transcription/GUITAR_TAB_SPEC.md` §GT1) landed the
audio-arm verdict: **adopt as proposed** — ship a **GuitarProFX-augmented TabCNN**
(~0.8 M params, public weights; the vanilla model's GuitarSet F1 0.748 drops to
0.447 zero-shot on real electric guitar, and re-rendering training audio with real
tones is the fix). TabCNN is *already* an emission scorer: six independent
per-string softmaxes, **no decoding of any kind** — its published metrics are a
plain per-frame argmax, so a constrained Viterbi over the same layer is a strict
improvement, not a lossy adaptation.

Our side of that contract is now IN the tree, testable with synthetic emissions:

- **`tab_emission_decoder.dart`** — `TabEmissionModel` seam (audio →
  `TabEmissionFrames`) + `decodeTabEmissions()`, a **per-string temporal
  Viterbi** that holds each string on a stable fret (kills the single-frame flips
  argmax follows), giving one-note-per-string + fret-range for free.
  `collapseTabFrames()` run-lengths the frames for a later rhythm/quantise stage.
  Pure Dart, 6 unit tests (incl. a decoy-spike case argmax fails and the decoder
  passes). Mirrors `f0_viterbi` decoding the CREPE/RMVPE lattice.

**The ABI contract CrispASR must match** (frozen here so the C++ has a target):

- output = **`[T, 6, 21]` log-probabilities** (`log_softmax`, NOT probs or
  logits — the DP sums costs and must never take log(0)), row-major
  (frame, string, class);
- **class 0 = string silent** ("closed"/not played); **class `k ≥ 1` = fret
  `k−1`** (class 1 = open, class 20 = fret 19) — `kTabClasses = 21`;
- plus the **frame hop in seconds** so we align to our own grid.
- ⚠ FretNet's tab head is NOT this per-string softmax shape — the decoder assumes
  TabCNN's. Pick FretNet only if note-level onsets matter (its real edge); for
  frame-level emissions feeding this DP, TabCNN is the fit.

Open refinement (documented, not blocking): the v1 decoder smooths each string
independently; a cross-string **hand-span** coupling within a frame is the next
increment. Per-string smoothing is already the strict improvement the spec
describes.

**Hard gate before any C++** (spec §5): **GuitarSet's license is UNVERIFIED**, and
it trains every audio-arm candidate — if it forbids commercial use of derived
weights, the audio arm dies. Check it first (cheap, can invalidate the arm). Same
for EGSet12.

## Which models (best current, by input)

Two distinct problems; CrispASR could ship either or both.

**A. Symbolic MIDI/score → tab positions** (upgrades `fromScore`, MusicXML/MIDI
import, the bridge pull — the common case).
- **Corpus:** **DadaGP** (~26k GuitarPro songs, tokenised — Sarmento et al.,
  ISMIR 2021) is the strongest open set; the *ProgGP / GTR-CTRL* line builds on
  it. Also mineable: MuseScore/GP corpora we already parse.
- **Model:** small seq2seq / BiLSTM-CRF or a tiny transformer (note-sequence →
  position-sequence labelling). This is a *small* model — position labelling,
  not generation. ONNX-exportable; likely runs on `onnx_runtime_dart` (pure
  Dart) as well as native ORT / ggml.

**B. Audio → tab positions** (a transcription that emits string/fret directly,
overlapping our existing F0/poly chain).
- **Corpus:** **GuitarSet** (annotated hexaphonic guitar).
- **Models:** **TabCNN** (Wiggins & Kim, 2019) and **FretNet** (2023) — small
  CNNs, proven, ONNX-exportable. These pair with the transcription seam, not
  `fromScore`.

Recommend **A first** — it's the direct upgrade to what shipped, smaller, and
needs no audio.

## How CrispASR should approach it (mirror transcription/SVC)

1. **Deliver an emission scorer, not a tab generator.** The model's output is
   per-position logits; our Viterbi + constraints stay the arbiter. This is the
   whole safety story.
2. **Package like the other models:** publish the ONNX/GGUF to a `cstr/*` HF
   repo, resolve+cache through CrispASR's own registry (as `crispasr_ffi_pitch`
   does), env-gated (`CRISPASR_TABARRANGE_*` / a `COMET_TABARRANGE_*` toggle),
   web-stubbed. Native-first; pure-Dart-ONNX path if the export is small enough
   to run under `onnx_runtime_dart`.
3. **Feature contract (freeze early):** input = the column MIDI list + tuning
   (string MIDIs) + capo + maxFret; output = a dense `[columns × candidates]`
   score, candidates in *our* enumeration order (send the enumeration, don't let
   the model invent one). Voicing-invariant to transposition where possible.
4. **License tags:** DadaGP is research-use — confirm the trained-weights licence
   is redistributable (MIT/CC-BY) before shipping, tag it in the model registry,
   and gate download behind the same license guard the BTC model uses (it's
   CC-BY-NC-SA and already gated). GuitarSet is CC-BY-NC — same caution.

## Acceptance (bit-exactness is NOT the target here)

Unlike the RVC/F0 ports, there's no single correct answer — tab is a preference.
Test against **playability + parity**, not bytes:
- **Playability invariants (must hold, already true of the baseline):** one note
  per string per column; every fret in `[0,maxFret]`; capo-correct sounding
  pitch; explicit `tabVoicings` preserved. Reuse the `tab_arranger_test.dart`
  assertions.
- **Quality metric:** total hand-movement cost + mean chord span over a held-out
  GP set, model vs. baseline — the model should reduce them (or match at lower
  variance). Report, don't assert a threshold.
- **A/B corpus:** re-fret a set of GuitarPro songs (strip their voicings, arrange,
  compare to the human tab) — % of positions matching the original fingering.
- **Fallback proof:** with the model absent/failed, `arrangeTab` returns exactly
  the baseline (regression-locked).

## Relay from the RVC/SVC port (unrelated seam, noted so it isn't lost)

Separate subsystem, but flagged by the CrispASR RVC agent for **our** SVC side:
their determinism harness exposes only **Site A** (`rnd`, the `z_p` latent). **Site
B — SineGen's additive noise, `(1, T×upp, 1)`, voicing-dependent and genuinely
random — is NOT exposed on our path** and must be made *injectable* on our side
for the three-way bit-exact harness to line up. Tracked under
`svc-voice-conversion-seam`, not part of this arranger work.

## Coordination

Standard: feature branch + a worktree that is a **sibling of `mus/`**; `dart
format` then `flutter analyze`; update the `docs/PLAN.md` board; no PRs, merge to
`main`. The seam addition to `tab_arranger.dart` is one optional param — land
that first (with a fake `TabPositionModel` in a test) so the model port has a
green target before any weights exist.
