# RMVPE handover — robust neural F0, and a vet correction

**Status: FEASIBILITY PROVEN, and the earlier vet was wrong on the hard point.**
The distributed RMVPE ONNX is a **pure convolutional U-Net (no GRU/LSTM)**,
runs end-to-end on `onnx_runtime_dart`, and emits the **same 360-bin pitch
salience as CREPE** — so it reuses CREPE's decode + `F0Estimator` seam. It is a
heavier, more-robust drop-in alternative to CREPE.

## Vet correction

The RMVPE *paper* describes a U-Net **+ GRU**; I flagged the GRU as a sequential
speed risk. **The actual shipped ONNX
([lj1995/VoiceConversionWebUI](https://huggingface.co/lj1995/VoiceConversionWebUI),
MIT) has no recurrent layer** — 351 nodes: `Conv`×124, `Relu`×117,
`ConvTranspose`×5, `AveragePool`×5, `BatchNorm`×6, skip-`Concat`×7. Pure conv ⇒
parallelizable, not GRU-bottlenecked. Licence is **MIT**.

## Feasibility — PROVEN (this session)

Downloaded `rmvpe.onnx` (**361 MB**) and ran it on `onnx_runtime_dart` (AOT):

- Input `input [1, 128, time]` — a **128-bin mel spectrogram** (the STFT/mel
  front end is EXTERNAL; compute it in Dart). Output `[1, 96, 360]` — a
  **360-bin pitch salience**, the same representation CREPE emits.
- **Ran clean**, ~3.45 s for 100 mel frames (≈1 s of audio at 16 kHz/10 ms hop),
  `Conv` 75% / `ConvTranspose` 2%, on a machine at **load ~90**, cold. Idle/warm
  is 2–4× faster. Offline-grade and **heavier than CREPE** (a 3-min song ≈
  minutes, not seconds). All ops supported (incl. the ConvTranspose fast path).

## What it buys vs CREPE

RMVPE is more robust than CREPE on noisy / breathy / polyphonic-ish vocals (it's
a strong vocal-pitch model). Same 360-bin output ⇒ **reuse `crepe.dart`'s
`decodeCrepeActivation` / weighted-argmax decode unchanged**, and drop it into
the existing `F0Estimator` seam next to CREPE.

## Remaining build (if pursued)

1. **Dart mel front-end:** 128-bin mel spectrogram at RMVPE's config (16 kHz,
   n_fft/hop matching the RMVPE reference — verify against
   `rvc/lib/rmvpe.py` mel params; typically n_fft=1024, hop=160, n_mels=128,
   fmin=30, fmax=8000). The app has FFT in `lib/core/audio/crisp_dsp/`.
2. **`rmvpe.dart`** (web-safe, takes a preloaded `OnnxModel`): mel → model →
   `[1, 96, 360]` → **existing CREPE decode** → `PitchTrack`. Mind the 96-vs-100
   frame reduction (pooling) when mapping frame → time.
3. **`rmvpe_model_store.dart`** (native, download-on-demand, `!kIsWeb`): the
   361 MB model — big; opt-in, native-only, explicit NOTICE (MIT). Consider an
   fp16 export to roughly halve the download.
4. Wire behind the `F0Estimator` seam and the Transcribe UI's "Neural pitch"
   toggle (add a CREPE-vs-RMVPE choice), reusing the `crepe_provider` pattern.
5. Tests: reuse the CREPE decode tests; model-gated end-to-end + mel parity vs
   the Python RMVPE mel.

## Recommendation

Feasible but **lowest priority** of the ONNX asks: it overlaps CREPE (already
shipped + UI-wired), is 361 MB, and is offline-grade/heavier. Build it only if
real recordings show CREPE failing on noisy/breathy vocals where RMVPE's
robustness earns the extra weight. If so, it's a small build (mel front-end +
reuse CREPE decode + seam) precisely because the 360-bin output matches CREPE.

## Reproduce

```bash
curl -sL -o rmvpe.onnx \
  https://huggingface.co/lj1995/VoiceConversionWebUI/resolve/main/rmvpe.onnx
dart run tool/bench.dart rmvpe.onnx --seq 100 --iters 1   # mel[1,128,100]→[1,96,360]
```

**Work in your own git worktree** (concurrent agents share the mus checkout).
