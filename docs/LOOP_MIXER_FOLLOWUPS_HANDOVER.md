# Loop Mixer — follow-ups handover (post-ladder)

**Status: not started, unclaimed.** The groovebox ladder (PLAN.md « Loop Mixer
2.0 ») shipped completely — slices 1–10, final `866350c`. These are the two
follow-ups that were explicitly scoped OUT of the ladder because each is a
session-sized effort of its own. Everything below is meant to be enough to
build end-to-end without re-deriving the plumbing (same intent as the original
`LOOP_MIXER_HANDOVER.md`, which worked).

Read first: `lib/core/audio/loop_engine.dart` (GrooveSpec, data patterns,
`cellsFor`), `lib/features/games/composition/groove_notation.dart`
(cells→Score), `loop_mixer_screen.dart` (capture harness, jam mode, share
sheet). The auto-memory `loop-mixer-groovebox` summarizes the architecture.

---

## A. Groove → Workshop / Song Book ("keep it as a real score")

### What it is

From the Loop Mixer's share sheet: **"Save to Song Book"** (v1) and optionally
**"Export MusicXML"** (v2). The groove becomes a real multi-part score — the
pedagogical payoff of the whole toy ("the thing you built by tapping cards IS
notation"), and the on-ramp to editing it in the Workshop, which already opens
anything the Song Book / MusicXML can hold.

### Building blocks that already exist (reuse, don't reinvent)

- **`groove_notation.dart`** — `grooveScore(cells, clef:)` already converts one
  track's `PatternCell` grid to a `Score` (4/4 bar packing, greedy durations,
  barline splits). Slice A1 generalizes this to multi-part.
- **`engine.cellsFor(id)`** — the exact cells the groove currently plays
  (variant-aware, progression-resolved for bass/chords, tiled for the rest;
  null for drums/beat). One call per part.
- **Song Book save pattern** — `free_sing_screen.dart:149` `_saveToSongBook()`
  → `UserSongsService.addSong(...)` (provider is already in the game test
  harness). Copy it.
- **Multi-part model + writer** — crisp_notation has the multi-part score
  model and a **multi-part MusicXML writer** (the Workshop's export sheet uses
  it; see the PLAN board note "crisp_notation has a multi-part *writer* for
  MusicXML alone"). Look at how `composition_workshop_screen.dart`
  `_generateExport('xml')` builds it.

### Build plan (slices)

1. **`grooveParts()` in groove_notation.dart** (pure, tested): for the enabled
   pitched tracks (priority voice · melody · chords · sparkle · bass), one
   part each — bass clef for bass, treble elsewhere; part names from the
   existing `loopMixerTrack*` l10n keys (pass resolved strings in, keep the
   module Flutter-free). Drums/beat are skipped in v1 (no percussion staff in
   the kid theme yet — say so in a comment, don't fake it).
2. **Share sheet entry "Save to Song Book"** + l10n de/en; disabled when no
   pitched track is enabled. Widget test via the existing seam.
3. *(optional)* **Export MusicXML** through the Workshop's writer path.

### Gotchas

- **The Workshop is opus's hot territory** (`composition_workshop_screen.dart`,
  `multi_part_canvas.dart` — see the PLAN board). You do NOT need to touch
  Workshop screens at all: Song Book + the MusicXML *writer* are the
  integration points. If you find yourself editing Workshop files, stop and
  re-read this.
- Split notes at barlines currently **re-attack instead of tying** —
  acceptable for a groove lead-sheet; if you add ties, do it in
  `grooveScore` and extend `groove_notation_test.dart` first.
- A 4-bar progression groove engraves 4 bars per part (cellsFor already
  resolves it) — assert that in the test like `groove_notation_test.dart`
  does for single parts.

---

## B. Native-AEC full-duplex jam grading ("the band listens back")

### What it is

Upgrade jam mode from its shipped v1 (platform `echoCancel` + headphones hint
+ live chord-fit colour) to **graded play-along over the audible groove**: the
speaker plays the loop, the Tier-3b AEC engine subtracts it from the mic, and
the cleaned signal is scored — per-note feedback like Play Along, but against
the groove the child built themself.

### Building blocks that already exist

- **`MicrophonePitchService` is already AEC-ready**: it takes an optional
  `aec: AecEngine`, captures from the engine's echo-cancelled `cleaned`
  stream, and the caller feeds the backing PCM via `pushReference(...)`. Read
  the doc comment on the `aec` field and **`docs/AEC_TIER3B.md`** before
  anything else.
- **The plugin**: `native/aec/` — standalone package, cleanroom MIT AEC +
  miniaudio, deliberately OUT of the app pubspec and excluded from the
  analyzer for CI safety (auto-memory `aec-tier3b-native-plugin`). Whatever
  wiring you add must keep that property: the app must build and stay green
  with the plugin absent (v1 jam mode is the fallback path — keep it).
- **The reference signal is trivially available**: the Loop Mixer plays ONE
  known WAV (`engine.renderLoop()` bytes) from a known clock phase (the
  screen's Stopwatch — see `_syncPlayback`/`_onLoopWrap`). You know exactly
  which PCM the speaker is emitting at every moment; feed that window into
  `pushReference` in time with playback. That alignment loop is the core of
  the work.
- **Scoring**: `engine.jamFit(midi, bar:)` for coarse colour (shipped), or
  `PlayAlongEngine` (`core/audio/play_along.dart`) if you want held-note
  grading against a specific target line (e.g. "sing the melody track").

### Build plan (slices)

1. **Reference-alignment core (pure Dart, no plugin)**: a small class that,
   given the loop PCM + the musical clock, yields the reference window for
   any wall-clock instant (handles seam wraps and phase-preserving swaps).
   Unit-test against synth-rendered loops — no audio hardware needed.
2. **Conditional AEC wiring**: construct `AecEngine` only where the plugin is
   present (follow AEC_TIER3B.md's integration pattern — do NOT add the
   plugin to the app pubspec); jam mode picks AEC when available, else the
   shipped echoCancel path. All platform-facing, still no grading change.
3. **Grading UI**: with the cleaned stream running, keep the jamFit colour
   chip but make it trustworthy at speaker volume; optionally a "follow the
   melody" mode scored by `PlayAlongEngine`.

### Verification (the part that makes this real)

- **The BlackHole acoustic loop** (auto-memory `blackhole-acoustic-loop-test`):
  BlackHole + `sox` coreaudio + `ffmpeg` make a fully self-driven acoustic
  test on this Mac — play the groove out, loop it back in as "mic", assert
  the cleaned stream detects a synthetic "instrument" tone mixed on top and
  NOT the groove. No human, no real mic, default device untouched.
- Platform builds on this Mac need the GEM env wrapper (CLAUDE.md «Building
  the Apple targets»); never run parallel platform builds (disk).
- Judge by the decoded outcome (does the detector hear the instrument, not
  the loop?), not by AEC-internal metrics — same discipline as the ladder's
  listen.dart roundtrips.

### Gotchas

- **CI safety is the hard constraint**: plugin stays out of pubspec, analyzer
  exclusion stays, v1 jam fallback stays. If CI needs the plugin to be green,
  the wiring is wrong.
- `MicrophonePitchService.echoCancel` (platform DSP) and `aec:` (Tier 3b) are
  different tiers — don't enable both blindly; read the tier docs.
- The mono MPM detector still can't transcribe polyphony: even perfect AEC
  gives you the *instrument's* monophonic line, which is exactly what jamFit
  / PlayAlongEngine expect. Don't promise chord grading.

---

## Shared ground rules (both efforts)

- Worktree = sibling of `mus/` (`../mus-<name>`), branch per effort; PLAN.md
  board claim + push BEFORE touching shared files; `dart format` first,
  whole-project `flutter analyze` last; tests in small per-file batches (the
  shared box thrashes under load); **`set -o pipefail` when a push gates on a
  piped test run** (auto-memory `pipefail-test-gates` — a red smoke reached
  main once without it).
- Hot shared files right now: `game_registry.dart`, ARBs, everything Workshop
  (opus), `tracker_engine.dart` + Loop Mixer files if the Tracker effort is
  still active — check the board.
- Acceptance bar set by the ladder: every slice ships with a headless
  roundtrip test that proves the FEATURE (listen.dart transcription, exact
  drum-row reconstruction, token roundtrips) — not just unit coverage.
