# AEC Tier 3b — native full-duplex echo cancellation (design)

Status: **milestone (a) shipped** (was: design / not started). Tiers 0
(headphones) + 1 (platform `echoCancel`) shipped; Tier 3a (pure-Dart
`echo_canceller.dart`) is a verified linear canceller that starves in-app on
alignment. This doc is the plan for the real fix.

### Progress — 2026-07-13
The standalone plugin package lives at **`native/aec/`** (its own pubspec,
deliberately **NOT** a dependency of the app, so CI never compiles or analyzes
it — see CI safety below). Milestone (a) is done and verified on this Mac:
- **`src/aec_dsp.c`** — the AEC core, a line-for-line **cleanroom C port of
  `lib/core/audio/echo_canceller.dart`** + the FFT from `chroma_analysis.dart`.
- **`src/aec_shim.c` + `src/miniaudio_impl.c`** — the miniaudio full-duplex host
  (aligned mic/reference on one clock) feeding lock-free SPSC rings.
- **`lib/aec_dsp.dart` / `lib/aec_engine.dart`** — hand-written `dart:ffi`
  bindings; `NativeAecEngine` implements the `AecEngine` API below.
- **`test/aec_erle_test.dart`** — offline **ERLE cross-check** over FFI, the C
  twin of `test/echo_canceller_test.dart` (same IR/seeds/thresholds → proves the
  port has no algorithmic drift). Both libs build on macOS; all tests green.

**Licensing decision (MIT-clean):** the original stack below recommended
SpeexDSP (BSD-3). To keep the tree MIT we instead **cleanroom-ported our own
AEC** (already ours, already ERLE-tested) and kept only **miniaudio (MIT-0)** as
the duplex host. SpeexDSP stays an *optional* future component behind a build
flag if residual/nonlinear performance ever demands it — a separate, explicit
licensing call, not baked in.

**Milestone (b) also done — tested on real device audio (2026-07-13):**
- **Headless engine unit test** (`test/aec_engine_test.dart`): drives the
  `aec_engine_*` int16 ring/framing/conversion path via a test pump (no device)
  — ERLE + near-end + raw-tap round-trip all green.
- **Live check** (`tool/live_check.dart`, outside `test/` so CI never opens a
  device): (1) null-backend duplex **lifecycle** — the realtime callback fires,
  frames flow; (2) **BlackHole 2ch loopback** (system default untouched) — plays
  a white-noise reference and cancels its loopback echo at **≈44 dB ERLE** (raw
  RMS ~2079 → cleaned RMS ~13). Real device audio, self-driven, no human/mic.
- Key: a short device **period** (`setPeriod(256)`) decoupled from a longer AEC
  **block** (`frame: 4096`) — the standard short-hop / long-filter arrangement,
  so the acoustic round-trip delay stays inside the filter tail.

**Milestone (c) done — app-side AEC seam:** `lib/core/audio/aec_engine.dart` is
an app-owned abstract `AecEngine`; `MicrophonePitchService` takes an optional
one and, when present, analyses its echo-cancelled `cleaned` stream instead of
the raw `record` mic (recorder is now lazy so AEC mode is headless), with a
`pushReference()` for the backing PCM. The app never imports the native package,
so CI stays green with no native code. Fake-driven test:
`test/microphone_aec_seam_test.dart`.

**Milestone (d) done — Flutter FFI plugin for all 5 platforms:** `native/aec` is
now a real Flutter FFI plugin (`pubspec` `ffiPlugin: true` ×5; `src/CMakeLists.txt`
for Android/Linux/Windows; podspecs + `Classes/` forwarders for macOS/iOS;
android gradle). Portability hardening: the SPSC rings use miniaudio's
`ma_pcm_rb` instead of hand-rolled C11 atomics (MSVC has no `<stdatomic.h>`), and
`CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS` exports the FFI symbols on MSVC. Verified by
the isolated **`aec-native` CI** (paths-filtered, never touches the app):
`lib-and-tests` (build + offline ERLE/engine tests) green on **ubuntu + macOS +
windows**, and `example-build` (a throwaway app depending on the plugin, built
with `flutter build`) green on linux/macOS/windows. The macOS example app was
also built locally.

Remaining: **final wiring** — add the plugin to the app `pubspec.yaml` behind a
runtime capability check + a `NativeAecEngine`→`AecEngine` adapter (kept out
until we're comfortable it's green on mobile too) → **(e) on-device tuning**
(iOS/Android; add a double-talk detector / residual suppression, or swap in
SpeexDSP BSD-3 behind a flag, only if real-room residual echo proves too strong
for the linear core).
See `native/aec/README.md`.

## Why a native plugin is required

The blocker is **alignment**, not the algorithm. In Flutter, `audioplayers`
(output) and `record` (input) are separate plugins on separate clocks — no
shared timebase, tens of ms of drift. A real AEC needs the reference (what was
played) and the mic aligned to ~a sample. Only a **single native audio engine
that owns both playback and capture** can provide that. So Tier 3b = one plugin
that:
1. Opens a full-duplex stream (mic in + speaker out on one clock).
2. Runs a battle-tested AEC (delay tracking + double-talk detector + residual
   suppression) — the parts Tier 3a lacks.
3. Emits the cleaned near-end PCM to Dart, where the existing
   `StreamingAudioAnalyzer` / `PitchDetector` consume it unchanged.

## Recommended stack (all BSD/MIT/Apache)

- **Full-duplex host: [miniaudio](https://miniaud.io)** (single-header, MIT-0 /
  public-domain). One `ma_device` in **duplex** mode gives synchronized
  `(input, output)` callbacks on all five targets — the shared clock we need.
  Alternative: Oboe (Android, Apache) + AVAudioEngine (Apple) natively, but
  miniaudio is one codebase for all platforms.
- **AEC: [SpeexDSP](https://github.com/xiph/speexdsp) `speex_echo`** (BSD-3).
  ~1k lines of portable C (MDF frequency-domain adaptive filter + DTD),
  self-contained (bundles its own FFT). Smaller and simpler to vendor than
  WebRTC AEC3 (also BSD, but large C++). Start with Speex; swap to WebRTC AEC3
  only if residual/nonlinear performance demands it.

## Architecture

```
                       ┌──────────────── native plugin (C, via FFI) ───────────────┐
 speaker  ◀── ma_device(duplex) ──▶  mic
   ▲            │  output cb: pull the app's reference frame (ring buffer)         │
   │            │  input  cb: mic frame                                            │
 backing        │  → speex_echo_cancellation(mic, reference) → cleaned near-end    │
 (synth) ───────┼──────────────────────────────────────────────────┐             │
                └───────────────────────────────────────────────────┼─────────────┘
                                                                     ▼
 Dart:  AecEngine.reference(pcm)  →  ring buffer          AecEngine.cleaned : Stream<Uint8List>
                                                                     ▼
                                            StreamingAudioAnalyzer → PitchReading (unchanged)
```

Key contract: the app **hands the plugin the reference it is about to play**
(the same synth PCM the backing uses), the plugin plays it AND uses it as the
AEC reference, and returns the cleaned mic. That closes the loop with perfect
digital reference + a shared hardware clock.

## Dart API (the plugin's surface)

```dart
abstract class AecEngine {
  Future<void> start({int sampleRate = 44100, int frame = 256});
  /// Queue reference PCM16 to be played AND cancelled.
  void reference(Uint8List pcm16);
  /// Cleaned near-end (mic minus echo), frame by frame.
  Stream<Uint8List> get cleaned;
  Future<void> stop();
}
```
`MicrophonePitchService` would gain an optional `AecEngine`: when present and
backing is on, feed the backing PCM to `reference()` and analyze `cleaned`
instead of the raw `record` stream. Everything above stays identical.

## Build (per platform, the fiddly part)

- **FFI bindings** via `ffigen` over a tiny C shim (`aec_open/reference/read/
  close`) that wraps miniaudio + speex. Vendor `miniaudio.h` + the ~15 speexdsp
  echo files under `native/`.
- macOS/iOS: CocoaPods `.podspec` compiling the C (respect the GEM-env wrapper,
  see CLAUDE.md). Android: `CMakeLists.txt` + Gradle externalNativeBuild.
  Linux/Windows: CMake. This is the bulk of the work and the CI risk.

## CI safety (mandatory — multi-agent, Linux CI)

Native compilation must not red the shared CI. Do the whole build **in an
isolated branch/worktree**, keep the plugin **out of the app's `pubspec.yaml`**
until it compiles green on every CI platform, and only then wire it in behind a
runtime capability check (fall back to Tier 0/1 when absent). Never land
half-built native code on `origin/main`.

## Verification plan

1. **Unit (host, offline):** feed the C AEC a digitally-aligned mic+reference
   mix; assert ERLE, mirroring `test/echo_canceller_test.dart` (the C output
   should match the Dart core within tolerance — a nice cross-check).
2. **Loopback (this Mac):** the BlackHole rig — play a reference through the
   plugin while it captures, confirm cancellation on real device audio.
3. **On-device (human):** speaker backing during play-along without headphones;
   confirm pitch scoring still tracks the user, not the speaker.

## Effort

Days–weeks: most of it is the 5-platform native build + on-device tuning, not
the algorithm (SpeexDSP is done). Sequence: (a) C shim + FFI + macOS build +
offline ERLE test → (b) BlackHole loopback → (c) wire into
`MicrophonePitchService` behind a flag → (d) Android/iOS/Windows/Linux builds →
(e) on-device tuning.
