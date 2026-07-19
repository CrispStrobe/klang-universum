# W-SEP enablement handover — Open-Unmix on `onnx_runtime_dart`

**Status: the apparent runtime "RangeError" is NOT an `onnx_runtime_dart` bug.
It is an ONNX-export dynamic-shape *baking* artifact. Open-Unmix runs correctly
on our runtime when the frame count matches the export, and the clean fix is
fixed-length chunking. No engine surgery is required.** This corrects the
"days of runtime work" blocker in
[`TRANSCRIPTION_SEP_FEASIBILITY.md`](TRANSCRIPTION_SEP_FEASIBILITY.md).

This doc is a standalone brief for a fresh agent to (1) confirm the root cause,
(2) produce a dynamic-safe Open-Unmix ONNX, and (3) wire it into the existing
`stems.dart` `Separator` seam so "transcribe the melody from a full song" works.

---

## 1 · Root cause (proven)

Export the umxhq vocals core and run it on `onnx_runtime_dart` (`tool/bench.dart`
in the `onnx_runtime_dart` repo):

| export trace length | run frames | result |
|---|---|---|
| 100 | 100 (match) | ✅ runs — `wall ~2.5 s` (JIT, cold, loaded box), LSTM 88.6% |
| 100 | 150 (mismatch) | ❌ `Cannot broadcast [100,1,2,2049] and [150,1,2,2049]` at `/Mul_2` |
| 200 | 100 (mismatch) | ❌ `RangeError` at `/Tanh` (reshape to baked [200,1,512]) |

The `[100,…]`/`[200,…]` tensors are **constants baked at trace time** —
Open-Unmix's `x = x + self.input_mean` / `x = x * self.input_scale`
(`openunmix/model.py` `OpenUnmix.forward`) broadcasts `input_mean` (shape
`[nb_bins]`) up to `[nb_frames, 1, 2, nb_bins]`, and the legacy TorchScript ONNX
exporter freezes `nb_frames` to the trace length **despite
`dynamic_axes={'spec': {3: 'frames'}}`**. The runtime is then correctly refusing
to broadcast a frozen `[100,…]` constant against a `[150,…]` input.

**Ruled out (so nobody re-checks):** the runtime handles dynamic reshapes fine —
a standalone 3-layer BiLSTM(512) runs at any `--seq`, and a minimal
`permute → slice → reshape(-1,C*bins) → Linear → BN → reshape(frames,…) → Tanh`
graph runs at `--seq` 50/100/200 with no error. The failure is specific to the
real export's baked broadcast constants, i.e. **export-side, not runtime-side.**

---

## 2 · Fix the export (pick one)

**Option A — fixed-length chunking (recommended).** Separators process audio in
fixed windows anyway. Export the core at ONE fixed frame length `T` (e.g. 256),
then in Dart slide a `T`-frame window over the spectrogram with overlap and
overlap-add the masks. A fixed-`T` ONNX has no dynamic axis, so nothing bakes
wrong. Cheapest, most robust. Cost: windowing + overlap-add code in Dart.

**Option B — make the export truly dynamic.** Either (a) use the new
`dynamo=True` exporter (`torch.onnx.export(..., dynamo=True)`), which tends to
keep symbolic dims, or (b) patch the core so `input_mean`/`input_scale` stay
rank-1 and broadcast at runtime (avoid the traced expand), then re-verify at
several `--seq`. If it runs at 100/150/300 unchanged, it's dynamic-safe. Then a
single ONNX handles any song length. Riskier (export internals), but no Dart
windowing.

Verify whichever path with `tool/bench.dart <model>.onnx --seq N` at **several
different N** — all must run without a broadcast/RangeError.

---

## 3 · Remaining integration (after a dynamic-safe ONNX)

1. **Dart STFT/iSTFT.** umxhq uses `n_fft=4096`, `hop=1024`, centered, with the
   model's window. The app already has spectral DSP (`lib/core/audio/crisp_dsp/`)
   — reuse or add a matching STFT. Feed magnitude `[1, 2, 2049, frames]`; apply
   the predicted mask to the complex spectrogram; iSTFT back to a waveform.
2. **`separate_model_store.dart`** (NEW, native-only, mirror
   `crepe_model_store.dart`): download-on-demand of the 4 target models
   (~142 MB total — be explicit in the NOTICE; MIT, from
   [sigsep/open-unmix](https://github.com/sigsep/open-unmix-pytorch), weights on
   Zenodo). `!kIsWeb`-guarded.
3. **`separate.dart`** (NEW, web-safe, takes preloaded models): implement the
   injected `Separator` typedef from `stems.dart`
   (`Future<Stems> Function(Float64List, int)`), returning `(vocals, bass,
   drums, other)`. `stems.dart`'s `transcribeStems` already assembles a
   `MultiPartScore` from stems — that glue is done and tested with a
   `fakeSeparator`; you are supplying the real one.
4. **Highest-value slice first:** vocals-only. Separate the vocal stem →
   run the ALREADY-SHIPPED `crepeF0` on it (behind the `F0Estimator` seam) →
   the lead-melody transcription of a full song. Ship this before the full
   4-stem multi-part; it's the compelling demo and needs one target model, not
   four.
5. CLI demo: `bin/transcribe_song.dart` (NEW; do not touch `bin/listen.dart`).

---

## 4 · Performance context

Cost is ~88–98% the 3-layer BiLSTM(512). AOT-benched standalone BiLSTM:
~0.19 ms/frame (min-wall) to 0.33 ms/frame (per-op) **on a machine at load ~90**
— idle is 2–4× faster. A 3-min song ≈ 7 750 frames × 4 targets ⇒ **~15–45 s
under load, ~5–20 s idle** for the neural part, plus Dart STFT. Offline-usable
behind a spinner; native-only, opt-in. (The 2.5 s/100-frame number above is
JIT-cold and not representative — measure AOT/idle.) Quality is mediocre (umxhq
vocals SDR ~5–6 dB); fine for "isolate vocal → CREPE the melody," not clean stems.

---

## 5 · Reproduce (in the `onnx_runtime_dart` repo)

```bash
uv pip install --python .venv-crepe/bin/python openunmix
.venv-crepe/bin/python - <<'PY'
import torch
from openunmix import umxhq
core = umxhq(targets=['vocals'], device='cpu').target_models['vocals']; core.eval()
T = 100
torch.onnx.export(core, torch.rand(1,2,2049,T), "/tmp/umx.onnx",
    input_names=['spec'], output_names=['mask'],
    dynamic_axes={'spec':{3:'frames'},'mask':{0:'frames'}}, opset_version=17, dynamo=False)
PY
dart run tool/bench.dart /tmp/umx.onnx --seq 100   # runs
dart run tool/bench.dart /tmp/umx.onnx --seq 150   # broadcast error (baked 100)
```

## 6 · Acceptance criteria

- A dynamic-safe (or fixed-`T` + chunked) Open-Unmix vocals ONNX that runs on
  `onnx_runtime_dart` at multiple lengths with no shape error.
- `separate.dart` implementing `stems.dart`'s `Separator`; a model-gated test
  (skip-if-absent) on a short synthetic vocal+backing mix → a vocal stem whose
  `crepeF0`→`segmentNotes` recovers the melody with a reasonable note-F.
- Deterministic no-model tests (STFT round-trip; stem shapes) that run in CI.
- Model NOTICE (MIT, open-unmix) shipped alongside the download.

**Work in your own git worktree** (concurrent agents share the mus checkout).
