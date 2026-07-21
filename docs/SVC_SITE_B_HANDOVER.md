# RVC/SVC Site-B injectable noise — status + remaining

**Status: MECHANISM SHIPPED on our side — no ONNX re-export needed.** Site B (the
SineGen additive noise) is an **in-graph `RandomNormal`** that `onnx_runtime_dart`
executes, so making it injectable was a runtime hook + an `rvc.dart` seam, not a
model re-export. What's left is a graph-presence check + the end-to-end 3-way
harness run (needs the licence-gated RVC model + the Python reference).

Background: auto-memory `svc-voice-conversion-seam`; the CrispASR RVC determinism
proof (three RNG sites: A = z_p latent, phase = a zeroed draw, B = SineGen
additive noise).

## The three sites — where each stands

- **Site A** (`rnd`, the flow/z_p latent `[1,192,T]`) — a graph **input**;
  injectable today via `rvcConvert(..., rnd:)` (`rvc.dart`).
- **Phase** — `harmonic_num == 0` → a single draw the model zeroes; **injecting
  zeros is provably equivalent** (bit-identical, proven both sides). It's a small
  `RandomUniform`; nothing to do.
- **Site B** — the SineGen **additive** noise `(1, T×upp, 1)`, a big
  `RandomNormal`. `onnx_runtime_dart` mean-fills it by default (≈ zeros).
  **Now injectable** — see below.

## What shipped

- **`onnx_runtime_dart` `OnnxRandomInject`** (`4dc258e`) — a process-global
  `provider(op, shape)`; a non-null buffer of the **matching flat length** is used
  verbatim by `RandomNormal`/`RandomUniform` instead of the default fill. Routing
  is by length, so injecting the one buffer sized to Site B (`T×upp`) hits that
  node and the tiny phase `RandomUniform` (length 1) falls through untouched — no
  execution-order knowledge, no re-export. +3 tests.
- **`rvc.dart`** — `rvcConvert(..., Float32List? sourceNoise)`: sets the provider
  to route `RandomNormal → sourceNoise` around the run (restored after). A TEST
  affordance; production `convert()` leaves it null.

## ⚠ The trap the ggml agent verified — inject the RAW draw, NOT the scaled noise

Their C++ (rvc_svc.cpp) applies the noise **voicing-dependently AFTER the draw**:
`out = sin(phase)·sine_amp·uv + na·noise[i]`, where `na` is **11× different**
voiced vs unvoiced (`noise_std = 0.003` when voiced, `sine_amp/3 = 0.0333` when
not). The graph does the same scaling **downstream of the `RandomNormal`**. So:

- inject the **raw `N(0,1)`** at the `RandomNormal` node (exactly what our seam
  does — `op == 'RandomNormal' ? sourceNoise`), and let the graph apply the UV
  scaling. Do **NOT** pre-scale in `rvc.dart`.
- if any scaling were folded in on either side, the buffers would match while the
  outputs don't — reads as a port bug, is actually a contract mismatch.
- length is **`T × upp`** (frame count × NSF upsample product), **not `T`** — the
  harness sizes `sourceNoise`; our length-routing matches it.

The ggml/CrispASR side already exposes both `noise_zp` (192·T) and `noise_sine`
(T×upp) over the C ABI (`rvc_svc_convert` / `crispasr_session_convert`) — nothing
needed from them for the wiring.

## Remaining (needs the RVC model + Python ref)

1. **Confirm our exported RVC graph actually contains the Site-B `RandomNormal`
   node** (the op-support + the NSF-source phase `RandomUniform` we already run
   strongly imply the source module is in-graph, not folded). If an old export
   folded the additive noise away, THEN a re-export exposing it is needed — but
   the injection mechanism above is ready either way.
2. **Run the 3-way harness** — Python-ref, `rvc.dart` (feed `rnd` = Site A,
   `sourceNoise` = Site B, phase = zeros), ggml — same buffers in.
3. **Acceptance = a tight epsilon, NOT literal 0** (agreed with the ggml agent):
   ggml↔Python hit `max_abs 0` because both are CPU-f32 with identical op
   ordering; the Dart/ONNX runtime is a **third numerical environment**, so
   ~1e-6/1e-7 is accumulation order, not a wiring bug. Gate on `max_abs < 1e-5`
   (revisit only if it's larger). Add it to the RVC reference-dumper stages.

## Coordination

Feature branch + a worktree; the model+ref harness run is the only gating piece
left; no PRs, merge to main; report the epsilon that lands into
`svc-voice-conversion-seam`.
