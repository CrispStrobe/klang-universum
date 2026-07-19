# Tracker replayer — effect coverage audit (read-only)

**By:** opus (libraries-and-tab), 2026-07-19 · **For:** @tracker-replayer (owns
`lib/core/audio/tracker_replayer.dart`) · **Method:** read-only source audit,
**no engine edits**. This refines backlog item **B) Replayer effect coverage**
(`docs/PLAN.md`) with current ground truth — the backlog list (2026-07-19) is
**stale**: several effects it calls "still-missing" are now implemented.

The state machine is `ReplayVoice` (armRow → per-tick `tick(k)`); flow commands
(Bxx/Dxx/Fxx/E6x) are resolved in `walkFlow`. Trajectories are unit-testable
pure via `traceChannel(cells, {ticksPerRow}) → ChannelTrace`
(`pitchAt/volumeAt/retriggerAt(r,k)`).

## Coverage — top-level commands 0x0–0xF (all 16 present ✅)

| Cmd | Effect | Status |
|----|--------|--------|
| 0xy | Arpeggio | ✅ per-tick cycle base/+x/+y |
| 1xx | Porta up | ✅ |
| 2xx | Porta down | ✅ |
| 3xx | Tone porta | ✅ no-overshoot |
| 4xy | Vibrato | ✅ sine only |
| 5xy | TonePorta + volslide | ✅ |
| 6xy | Vibrato + volslide | ⚠️ **present but buggy** — see Defect 1 |
| 7xy | Tremolo | ✅ sine only |
| 8xx | Set pan | ✅ |
| 9xx | Sample offset | ✅ |
| Axy | Volume slide | ✅ ⚠️ ignores the fine **F-nibble** (see G3) |
| Bxx | Position jump | ✅ walkFlow |
| Cxx | Set volume | ✅ |
| Dxx | Pattern break | ✅ walkFlow |
| Exy | Extended | ✅ partial — table below |
| Fxx | Set speed / tempo | ✅ walkFlow (split at 0x20) |

## Coverage — extended Exy sub-commands

| Sub | Effect | Status |
|----|--------|--------|
| E1x | Fine porta up | ✅ *(backlog wrongly lists as missing)* |
| E2x | Fine porta down | ✅ *(ditto)* |
| E6x | Pattern loop | ✅ walkFlow |
| E9x | Retrigger | ✅ *(backlog wrongly lists as missing)* |
| EAx | Fine vol up | ✅ |
| EBx | Fine vol down | ✅ |
| ECx | Note cut | ✅ *(backlog wrongly lists as missing)* |
| EDx | Note delay | ⚠️ **present but buggy** — see Defect 2 |
| E3x | Glissando control | ❌ missing |
| E4x | Vibrato waveform | ❌ missing (LFO is always sine) |
| E5x | Set finetune | ❌ missing |
| E7x | Tremolo waveform | ❌ missing (always sine) |
| EEx | **Pattern delay** | ❌ missing — **timing-significant** |
| E0x/E8x/EFx | filter / sync / funk-loop | ⬜ rare, low priority |

## Not implemented — XM/S3M/IT extras (beyond MOD)

- **Rxy** retrigger + volslide (backlog-named)
- **Fine F-nibble slides** in Axy / 1xx / 2xx (backlog-named "FF nibble")
- **Gxx** global volume, **Hxy** global-vol slide
- **Mxx** set channel volume, **Nxy** channel-vol slide (backlog group B, bullet 2)
- **Pxy** panning slide, **Txy** tremor, **Kxx** key-off, **Lxx** env position,
  **Xxx** extra-fine porta
- **Volume-column mini-commands** — the volume column exists as a static level
  (`applyVolumeColumn`, Cxx-equivalent) but not the XM vol-column
  vibrato/porta/pan sub-commands.

## Fix these FIRST — coverage that plays wrong audio (already on the board)

Both from the prior read-only audit (`docs/PLAN.md`, "opus (audit) → REPORT for
@tracker-replayer"), still marked **NOT fixed**. Wrong coverage is worse than a
gap — reproduce them before adding anything new:

1. **6xy corrupts vibrato memory** — `armRow` shares the 4xy/6xy nibble parse, so
   a 6xy volslide param overwrites `_memVibDepth`/`_memVibSpeed` (and invents
   vibrato with no prior 4xy). Split 6xy to set only `_memVolSlide`.
2. **EDx re-attacks a still-ringing prior note** — `noteStartSample` is reset at
   row start for a pending delay, restarting the old note's envelope during ticks
   0..x-1. Reset only when the note actually fires.

## Then, by value ÷ effort (missing coverage)

1. **EEx pattern delay** — repeats the current row x+1 times; a song using it
   currently plays at the **wrong length/rhythm** (silent no-op today). Belongs in
   `walkFlow` (row-level flow, like E6x). Highest audible impact of the gaps.
2. **Fine F-nibble slides (Axy/1xx/2xx)** + **Rxy** — common in S3M/XM; small,
   local to the slide/retrigger logic. `_isVolSlide` already computes `x,y`
   nibbles — add the `x==0xF`/`y==0xF` fine-once branch.
3. **E4x / E7x waveform select** (sine → ramp/square/random) + **E5x finetune** +
   **E3x glissando** — refinements to existing LFO/porta; each is a small
   per-tick branch.
4. **Gxx global / Mxx channel volume** — needs a scalar in the mix stage
   (`mixStems`), not just per-voice; larger, do last.

## Test pattern (matches the repo's convention)

Per-tick trajectory test via the pure API — no audio needed:

```dart
// EEx pattern delay: a 1-row pattern with EE1 should render two rows of audio.
final t = traceChannel([TrackerCell(midi: 60, fxCmd: kFxExtended, fxParam: 0xE1)]);
// (EEx is walkFlow-level — assert replaySong(...).pcm length doubles instead.)

// Rxy: retrigger every y ticks while volsliding by x.
final t = traceChannel([TrackerCell(midi: 60, fxCmd: kFxRetrigVolSlide, fxParam: 0x23)]);
expect(t.retriggerAt(0, 3), isTrue);          // retrigger on tick 3
expect(t.volumeAt(0, 3), lessThan(kMaxVolume)); // …and volume slid down
```

Then a synth → `dart run bin/listen.dart --wav` acceptance where the effect
changes pitch/level audibly (the pattern used elsewhere in the tracker suite,
e.g. `midsong_timing_acceptance_test.dart`).

---
*Read-only audit. I did not touch `tracker_replayer.dart` or its tests — the
lane is @tracker-replayer's. Relaying so it can be actioned with full context.*
