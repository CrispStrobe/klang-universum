# Automatic Play-Along — plan & status

Live pitch/chord detection from the mic, turned into real practice modes:
tuner, sing-along, play-along with a moving score, and games. Everything sits
on one pure-Dart detection core so it stays testable headlessly and from a CLI.

## Architecture (done, `feature/pitch-detection-spike`)

```
mic (record plugin) ─┐
WAV file ────────────┼─→ StreamingAudioAnalyzer ─→ PitchReading  (mono, MPM/NSDF)
stdin PCM (CLI) ─────┘        (sliding window)   └─→ ChordReading  (chromagram+templates)
```

- `core/audio/pitch_analysis.dart` — McLeod Pitch Method detector → note + cents.
- `core/audio/chroma_analysis.dart` — FFT + chromagram + fuzzy chord templates.
- `core/audio/streaming_analyzer.dart` — pure-Dart windowing, shared by mic + CLI.
- `core/audio/microphone_pitch_service.dart` — the only plugin-facing file.
- `core/audio/wav_io.dart` — PCM16 WAV reader.
- `bin/listen.dart` — CLI: `--wav`, `--stdin` (live), `--selftest`, `--chords`.
- `core/audio/play_along.dart` — scoring engine for play/sing-along (see below).

Detectors are proven headlessly (synth-based unit tests, all green) and via the
CLI on real audio; the mic path is verified on macOS. Only the live *acoustic*
feel (latency, real-instrument chord accuracy) still wants on-device tuning.

## Modes & games

### 1. Tuner — DONE (real)
Chromatic/cello tuner: big note, cents needle, in-tune zone. Cello-first
(fretless intonation is where it matters). Keeper tile.

### 2. Play-along (moving score) — DONE (v1)
A note-highway: target notes scroll past a "now" line; you play/sing and the
live pitch is scored against each note (correct pitch within a cents window for
enough of its duration = hit). `PlayAlongEngine` is pure-Dart and unit-tested.
Cello exercise chart to start.

### 3. Sing-along — DONE (v1)
The same engine + screen with a vocal-range melody preset. Voice is the same
monophonic detection; only the chart/labelling differs.

### 4. Chord listener — DONE (spike)
Names the chord you strum/play with runner-up guesses + a chroma bar chart.

## Known constraints / follow-ups (not yet done)
- **Backing audio vs. mic:** playing the melody through speakers while the mic
  listens causes the mic to detect the *speaker* (we deliberately disable echo
  cancellation for pitch accuracy). v1 play/sing-along therefore scrolls the
  score without audible backing, with a "preview" listen before you start; real
  backing needs headphones or an AEC path. Documented, not solved.
- **Localization:** the new modes use literal English strings for velocity.
  Promote to `l10n` (de/en) before release — one `AppLocalizations` key per
  title/subtitle, same as existing games.
- **Progress/stars:** play/sing-along report a score but don't yet write to
  `ProgressService` or define `kStarThresholds` brackets. Wire once the scoring
  feel is tuned on-device.
- **Real-instrument tuning:** `scoreThreshold`/`energyGate`/`centsTolerance`
  are set against synth tones; retune against real mic input (use the CLI
  `--stdin`/`--wav`).
- **Phase 3 (full polyphonic transcription):** still out of scope; would layer
  on the same chromagram.

## Testing
- `flutter test` — unit tests for every detector + the play-along engine.
- `dart run bin/listen.dart --selftest --chords` — headless smoke test.
- `dart run bin/listen.dart --stdin` fed from `sox`/`ffmpeg` — live mic.
- macOS/iOS builds need the GEM-env wrapper (see CLAUDE.md / appstore.md).
