# W-SEP feasibility memo — source separation in pure Dart

**Question:** can we run a real music source separator (vocals / drums / bass /
other) in pure Dart on `onnx_runtime_dart`, fast enough to be useful for the
"transcribe the melody from a full song" flow (separate → then CREPE / Basic
Pitch per stem)? The `stems.dart` assembly glue already exists with an injected
`Separator` typedef; this memo is about whether a concrete separator is viable.

**Verdict: PLAUSIBLE for Open-Unmix (not the htdemucs dead-end), but blocked
today by a runtime gap, and the quality is mediocre.** Details below.

## Candidates

| Model | Licence | Arch | Size | Verdict |
|---|---|---|---|---|
| **htdemucs** (Demucs v4) | MIT | transformer + deep conv U-Net | ~180 MB | ❌ measured earlier ≈ **1 hr/song** — huge FLOPs, not sequential-slowness. Dead-end in pure Dart. |
| **Open-Unmix** (umxhq) | MIT | 3-layer **BiLSTM(512)** over spectrogram frames + 2 dense | **35.6 MB × 4 targets ≈ 142 MB** | ⚠️ **speed-feasible** (tens of s/song), but see blockers. |

Open-Unmix is far lighter than htdemucs — the earlier "sequential ⇒ slow like
htdemucs" intuition conflated two things: htdemucs is slow because it is *huge*
(transformer), not merely sequential. Open-Unmix's recurrence is over a small
hidden dim, so it is cheap.

## What was measured (this repo, AOT `tool/bench.dart`)

Exported the umxhq **vocals** core to ONNX (`torch.onnx.export`, opset 17):
`spec[1,2,2049,frames] → mask[1,2,2049,frames]`. Ops: **3× LSTM** (the 3
bidirectional layers), 3× MatMul (fc1 2974→512, fc2, fc3), 3× BatchNorm, plus
reshape/transpose glue. All op types are implemented in `onnx_runtime_dart`.

The cost is ~entirely the BiLSTM. Benching a standalone 3-layer
bidirectional LSTM(512) — Open-Unmix's cost core — on `onnx_runtime_dart` AOT:

| seq (frames) | min wall | LSTM share |
|---|---|---|
| 100 | 99.9 ms | 98.3 % |
| 400 | 157.2 ms | 99.0 % |

⇒ per-frame slope ≈ **0.19 ms/frame/target** (min-wall) to **0.33 ms/frame**
(per-op mean). **Caveat: the dev machine was at load ~90 on 8 cores**, so these
are inflated — an idle machine is likely 2–4× faster.

### Extrapolation to a 3-minute song

n_fft 4096, hop 1024, 44.1 kHz ⇒ ~**7 750 frames**. Four targets:

- LSTM: 7 750 × 4 × (0.19–0.33 ms) ≈ **6–10 s** under load; ~**2–5 s** idle.
- Plus the fc1/fc2/fc3 MatMuls (fc1 is 2974→512 over 7 750 frames × 4) and a
  Dart-side 4096-pt STFT/iSTFT front/back end.
- Realistic order of magnitude: **~15–45 s/song under load; ~5–20 s idle.**

So it is **tens of seconds, not an hour** — offline-usable (behind a spinner),
unlike htdemucs.

## Blockers (why it is not a drop-in today)

1. **The full model does not run as-exported on `onnx_runtime_dart`.** Execution
   throws a `RangeError` at the `Tanh` after the fc1/bn1 reshape
   (`x.reshape(nb_frames, nb_samples, hidden)`) around the LSTM path — a
   dynamic-shape / reshape-handling gap for this graph pattern. The standalone
   BiLSTM runs fine, so the LSTM op itself is OK; the bug is in the reshape glue.
   **Fixing this is real runtime work (days, not hours)** and is the true gate.
2. **Quality is mediocre.** umxhq is the oldest/weakest modern separator (vocals
   SDR ~5–6 dB vs Demucs ~7–9 dB). Good enough for "isolate the vocal, then run
   CREPE on it," not for clean stems.
3. **STFT/iSTFT must be done in Dart** (the app has spectral DSP; needs a
   4096-pt STFT with the right window to match the model's training front end).
4. **Size:** ~142 MB (4 targets) ⇒ opt-in, native-only, download-on-demand.

## Recommendation

- **Do NOT build it speculatively now.** The compute is feasible, but the
  runtime reshape gap + Dart STFT + quality validation make it a multi-day
  effort, and the payoff (mediocre stems) is modest.
- **If "melody from a full song" becomes a priority**, the cheapest path is:
  (a) fix the `onnx_runtime_dart` reshape/dynamic-shape gap (needed anyway for
  other RNN graphs), (b) wire a Dart STFT, (c) export umxhq's 4 targets, feed
  `stems.dart`'s `Separator` seam, (d) run **CREPE** (already shipped) on the
  vocal stem for the lead melody. This single-stem-melody path is the
  highest-value slice and could ship before full 4-stem multi-part.
- **RMVPE** (see the separate vet) targets the same "vocal pitch from a mix"
  goal in one model, but is heavier (U-Net + GRU + mel front end). Given
  Open-Unmix→CREPE is feasible on speed, neither is a slam-dunk; both are
  gated on either a runtime fix (Open-Unmix) or a heavy port (RMVPE).

## Reproduce

```
uv pip install --python .venv-crepe/bin/python openunmix   # in onnx_runtime_dart
# export umxhq vocals core → ONNX (see this memo's git history / commit body)
dart compile exe tool/bench.dart -o /tmp/onnxbench
/tmp/onnxbench umxhq_vocals.onnx --seq 100 --iters 3   # → RangeError at /Tanh
/tmp/onnxbench bilstm.onnx --seq 100 --iters 3         # standalone LSTM: runs
```
