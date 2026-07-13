# aec_fullduplex — native full-duplex echo cancellation (AEC Tier 3b)

The native fix for speaker-mode play-along: cancel the app's own backing out of
the mic so pitch scoring grades the *user*, not the speaker. Implements the plan
in [`docs/AEC_TIER3B.md`](../../docs/AEC_TIER3B.md).

> **Status: milestone (a).** DSP core + FFI + macOS build + offline ERLE test
> land here. The miniaudio duplex host compiles; on-device capture (BlackHole
> loopback, then hardware) and the per-platform Flutter-plugin wrappers are the
> next milestones. **This package is intentionally NOT a dependency of the app**
> and is invisible to CI until it builds green on every platform.

## Why a native plugin

Flutter's `audioplayers` (out) and `record` (in) run on separate clocks — tens
of ms of drift, no shared timebase. A real AEC needs the reference (what was
played) and the mic aligned to ~a sample. Only one native engine owning both
playback and capture can provide that. Here that engine is **miniaudio** in
duplex mode.

## Design & licensing (MIT-clean)

Two layers, kept separate so the algorithm is testable without any audio device:

| Layer | File | License | Role |
|-------|------|---------|------|
| AEC core | `src/aec_dsp.c` | **MIT (ours)** | Constrained overlap-save FDAF + NLMS linear canceller. A line-for-line C port of the app's `lib/core/audio/echo_canceller.dart` + the radix-2 FFT from `chroma_analysis.dart`. |
| Duplex host | `src/aec_shim.c`, `src/miniaudio_impl.c` | **MIT (ours)** + miniaudio **MIT-0** | One `ma_device` in duplex mode; the callback plays the queued reference, uses the *same* samples as the AEC far-end, and streams back the cleaned near-end. |

The Tier-3b design doc originally suggested SpeexDSP for the AEC. SpeexDSP is
BSD-3 (permissive, but not MIT and carrying its own notice), so to keep the tree
MIT-clean we instead **cleanroom-ported our own AEC** — it's already ours and
already ERLE-tested. SpeexDSP remains an *optional* future component (behind a
build flag) only if residual/nonlinear performance ever demands it, and that
would be a separate, explicit licensing decision.

Bundled third-party license text lives in [`LICENSES/`](LICENSES/).

## Build & test (macOS, this session's verified path)

```bash
cd native/aec
cmake -S . -B build && cmake --build build      # builds libaec_dsp + libaec
dart pub get
dart test                                         # unit tests (no device)
```

`dart test` auto-locates `build/libaec*`; override with `AEC_LIBRARY_PATH`. On
this Mac, wrap the build with the GEM-env fix from the repo `CLAUDE.md` if pod
tooling interferes (`build.sh` does this for you).

### Unit tests (`dart test`, no audio device)
- **`test/aec_erle_test.dart`** — the C twin of the app's
  `test/echo_canceller_test.dart` (same IR/seeds/thresholds): drives the pure
  `aec_dsp_*` core over FFI, proving the port has no algorithmic drift.
- **`test/aec_engine_test.dart`** — drives the *engine* layer (`aec_engine_*`)
  via a test pump: PCM16 reference + mic through the exact realtime-callback
  rings/framing/int16↔double path, asserting ERLE + near-end preservation +
  raw-tap round-trip. Covers the plumbing the DSP-only test can't reach.

### Live check (`dart run tool/live_check.dart`, real device)
Deliberately outside `test/` so CI never opens a device. Two checks:
1. **Lifecycle** — starts the duplex device on miniaudio's `null` backend and
   confirms the realtime callback fires (cleaned frames flow at ~sample rate).
2. **BlackHole loopback** — routes playback+capture through "BlackHole 2ch"
   (system default untouched), plays white-noise reference, and measures ERLE.
   **Verified on this Mac: raw RMS ~2079 → cleaned RMS ~13, ≈44 dB ERLE** — the
   native AEC cancels real device-audio echo. (Skips gracefully if BlackHole
   isn't installed.)

`tool/live_check.dart` decouples a short device **period** (`setPeriod(256)`,
low round-trip delay) from a longer AEC **block** (`frame: 4096`, filter tail
that covers the delay) — the standard short-hop / long-filter AEC arrangement.

## Dart API

```dart
import 'package:aec_fullduplex/aec_engine.dart';

final aec = NativeAecEngine();
await aec.start(sampleRate: 44100, frame: 256);
aec.reference(backingPcm16);            // played AND cancelled
aec.cleaned.listen(analyzer.addPcm16);  // mic minus echo
await aec.stop();
```

`MicrophonePitchService` will gain an optional `AecEngine`: when present and
backing is audible, feed the backing PCM to `reference()` and analyse `cleaned`
instead of the raw `record` stream — everything above stays identical.

## Roadmap (from AEC_TIER3B.md)

- [x] (a) C shim + FFI + macOS build + offline ERLE test
- [x] (b) BlackHole loopback verification on this Mac (≈44 dB ERLE) + headless
      engine unit test + null-backend lifecycle check
- [ ] (c) wire into `MicrophonePitchService` behind a capability flag
- [ ] (d) Android / iOS / Windows / Linux Flutter-plugin wrappers, CI-green
- [ ] (e) on-device tuning (add DTD / residual suppression as needed)
