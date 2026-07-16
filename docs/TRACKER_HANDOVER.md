# Tracker (pattern sequencer) — handover

**Status:** not started. A **Studio-shelf** creative surface in the spirit of
ModEdit / FastTracker 2 / Scream Tracker 3 / Impulse Tracker, but **dual-audience**
(a 10-year-old can make a groove; an adult finds it genuinely cool). It is *not* a
faithful hex-grid clone — it takes what trackers **teach** (pattern thinking,
layering, arrangement, **sample-as-instrument**) and renders it touch-first, with
the density gated behind the Sandbox/Studio shelf — the same split Workshop uses.

The good news, twice over:
1. **The playback foundation already shipped.** The Loop Mixer (`32ebb96`) landed
   `mixStems` + the percussion generator in `synth.dart` and `loop_engine.dart`.
   A tracker is `LoopEngine` **with an editable pattern grid** — same offline-mix-
   then-loop-one-WAV engine, same `mixStems` call, same timing model.
2. **The sample DSP is already written (MIT, ours).** Creating and modifying
   sample instruments — the thing that makes it a *tracker* and not a step-
   sequencer — is a **mechanical port** of `CrispStrobe/crispaudio` (see §5). No
   research; the hard algorithms exist and are debugged.

---

## 1. The core idea — one pattern model, two skins

Don't build a "kid sequencer" and a "pro tracker." Build **one full tracker
document**, and give it **two views** — exactly how Workshop does Sandbox/Studio
over one score. The Sandbox view *hides columns*; it is never "Studio greyed out."

```
STUDIO (adult)                          SANDBOX (same pattern, 10yo)
┌────┬─────────────┬──────────┐         ┌───────────────────────────┐
│ Row│ Ch1  Ch2    │ Ch3  Ch4 │         │  🥁  🎸  🔔  🎤           │
├────┼─────────────┼──────────┤         ├───────────────────────────┤
│ 00 │ C-4 05 .. A04│ E-5 .. …│   ⇄     │  ●   ○   ●   ·   ← playhead│
│ 01 │ ... .. 40 …  │ ...      │         │  ·   ●   ·   ●            │
│ 02 │ E-4 05 v.. … │ G-5 …    │         │  ●   ○   ●   ·   (colored)│
└────┴─────────────┴──────────┘         └───────────────────────────┘
 full cell (note·instr·vol·fx),         big tap cells, pitch = color,
 keyboard entry, more channels,         scale-locked (can't sound bad),
 sample slots, order list               tap to place/remove
```

- **Sandbox** (kid): big colored cells (`pitchClassColor`, the Colour Melody
  trick), tap to place/remove, **scale-locked to C-pentatonic so any placement
  grooves**, instruments as friendly icons. The playhead sweep + layering is the
  "I made this!" moment.
- **Studio** (adult): the real tracker cell (`note · instrument · volume ·
  effect`), more channels, finer resolution, **keyboard entry** (desktop/web),
  chromatic freedom, pattern order-list, an optional **retro skin** (monospace,
  classic FT2/IT layout) as nostalgia bait.
- **The reveal is the fun.** A kid who levels up flips the shelf and the effect
  column appears — the tool grows with them. Discipline: the Sandbox must stay
  genuinely uncluttered (no disabled hex columns leaking through).

**The bridge feature that delights both audiences — build it early:**

> Record your voice → make it a robot / chipmunk / monster → play a tune with it.

To a 10-year-old that's the funniest thing ever. To an adult it's *sampling +
PSOLA / formant processing*. **Same button, same code** (§5).

---

## 2. It builds directly on what shipped (reuse, don't reinvent)

`lib/core/audio/loop_engine.dart` is the template. Read it first. What maps:

| Loop Mixer (shipped) | Tracker |
|---|---|
| `LoopTiming` (2 bars, eighth-step grid, integral ms/samples) | same clock; expose rows/steps + tempo |
| `LoopTrack.render` — a **fixed** authored pattern | an **editable** `List<Cell>` per channel |
| `mixStems([...stems], totalSamples:)` | **unchanged** — sum the channels' buffers |
| `wavBytes(...)` + `ReleaseMode.loop` player | **unchanged** — one buffer, looped |
| additive `renderSegmentsRaw` / `renderDrumPattern` | + a **pitched-resample renderer** for sampled instruments |

So a channel renders its editable pattern → `Float64List`, and `mixStems` sums the
channels exactly as it sums Loop Mixer tracks. The render/stem/WAV caching in
`LoopEngine` (per tempo, per enabled-set) is the pattern to copy for
"re-render only what changed."

Also reuse: `timbreFor(Instrument)` (the four built-in voices as instruments),
`renderDrumPattern`/`Drum` (percussion channel for free), the loop-player +
`Ticker` playhead pattern from `loop_mixer_screen.dart`, `pitchClassColor`
(`note_reading/note_colors.dart`), and the sandbox `GameInfo` registration shape
(no star bracket — put it in the `composition` module).

---

## 3. Instruments — three sources, one buffer type

Every instrument ultimately yields a mono sample buffer that the per-note
renderer resamples by pitch ratio (`2^(semitones/12)`, linear/cubic interp — the
same math already in `crispaudio/dsp/PitchShifter.ts`, ~30 lines). The three
sources:

1. **Additive (built-in):** the existing `Instrument` timbres — render per-note
   with `renderSegmentsRaw`. Free, already there. Fine for v1.
2. **Procedural chiptune (sfxr):** port `SynthEngine.generateSamples()` (§5) →
   tap "laser"/"coin"/"explosion"/"powerup" → an instant retro instrument. The
   classic tracker workflow; kid-delightful.
3. **Recorded + modified:** capture the mic (the app already has
   `microphone_pitch_service.dart` / `melody_recorder.dart` / `wav_io.dart`), then
   run the ported effect chain (§5) — pitch shift, formant, time-stretch, distort,
   bit-crush, ring-mod. This is the voice-sampling bridge and the "real tracker"
   feel.

Pipeline (everything is an offline `Float64List` transform — the app's ethos):

```
generate(sfxr) ─┐
record mic ─────┤─▶ effect chain ─▶ instrument sample ─▶ per-note pitched resample ─▶ mixStems ─▶ loop WAV
additive ───────┘
```

---

## 4. Build plan (slices)

**Slice 0 — pattern model + engine (pure Dart, Flutter-free).**
A `TrackerPattern` (channels × rows of `Cell{note?, instrument, volume, fx?}`) and
a `TrackerEngine` that renders each channel to a `Float64List` and `mixStems`-es
them, mirroring `LoopEngine` (incl. per-channel stem cache). Unit-test like
`loop_engine_test.dart`: editing a cell changes the bytes; empty pattern = silence
of the right length; mix never clips.

**Slice 1 — Sandbox skin + looping playback.**
The kid grid: N channels × steps, tap to place/remove, scale-locked, colored,
playhead. Reuse the Loop Mixer's `ReleaseMode.loop` player + `Ticker`. Register
the `GameInfo` (composition, no star bracket) + EN/DE ARB. Add a
`@visibleForTesting` tester seam (drive cell edits headlessly, assert bytes
differ / play doesn't throw) — mirror `GridComposerTester`.

**Slice 2 — sample instruments (the bridge).**
Port `SynthEngine.generateSamples` (procedural) **and** the record→effect path
(§5). "Record your voice → robot/chipmunk → play it." Per-note pitched resampler.
This is where it becomes a *tracker*; prioritize it over Studio depth.

**Slice 3 — Studio skin.**
Shelf toggle → full cell (volume + effect columns), more channels, keyboard
entry, chromatic, retro skin. One document underneath (§1). Don't fork the model.

**Slice 4 — arrangement + polish (optional).**
Pattern order-list / song mode, per-cell effect commands (arp/porta/vibrato as
per-channel modulation), gapless swap, tempo/speed. Stretch: load a real
`.mod`/`.xm` to play the classics (substantial parsers — later).

---

## 5. The DSP to port (from `CrispStrobe/crispaudio`, MIT, ours)

`crispaudio` was already refactored toward framework-free pure functions — the
port is mostly mechanical. House it in a new **`lib/core/audio/crisp_dsp/`**
(pure-Dart, Flutter-free, unit-tested like `synth.dart`; reusable beyond the
tracker). The app already ships a radix-2 FFT in `chroma_analysis.dart` — **reuse
it, don't port `utils/fft.ts`.**

**Tier A — port ~1:1.** Pure buffer math; the only Web-Audio touch is
`OfflineAudioContext` used as a *buffer allocator* — replace with `Float64List` +
sampleRate and the algorithm copies over:

- `engine/SynthEngine.ts` → **sfxr sample generator** (square/saw/sine/noise +
  ADSR/vibrato/arp/duty). `generateSamples()` is explicitly AudioContext-free.
  *The "make an instrument" button.*
- `dsp/PitchShifter.ts` (granular pitch shift), `dsp/TimeStretcher.ts` (PSOLA/OLA
  time-stretch), `dsp/FormantShifter.ts` — the voice-mangling core, ~100 lines
  each of Hann-window overlap-add.
- `effects/Distortion.ts` (tanh/hardClip/fuzz/wavefold transfer curves) +
  `effects/Reverb.ts` (IR generator; reverb = convolve with the app's FFT).

**Tier B — reimplement offline, textbook-short (~10–30 lines each).** These are
coded as native Web-Audio *nodes* only because that's free in a browser; offline
you write the difference equation:

- `Filter.ts` (BiquadFilterNode → RBJ-cookbook biquad), `BitCrush.ts`
  (→ `round(x·levels)/levels`), `Chorus.ts` / `Delay.ts` (→ ring buffer + LFO),
  `RingModulator.ts` (→ multiply by sine).

`voicelab/src/audio-processor.js` (735 lines) and `CrispFXR-web/src/App.js` are
the earlier, less-factored versions of the same algorithms — use `crispaudio` as
the source of truth; consult the others only if a detail is clearer there.

Keep the MIT notice when porting (the code is ours; `SynthEngine.ts` already
documents its own lineage from crispfxr).

---

## 6. Gotchas / coordination

- **Same sample length across channels**, or the mix mis-aligns / the loop
  clicks — derive every channel's total-ms from one tempo × bars (as `LoopTiming`
  does). Pitched-resampled one-shots must be placed on the grid and zero-padded to
  the step, not stretched to fill it.
- **Normalize the mix, not each channel** — that's `mixStems`' whole job
  (unit-peak-per-stem + soft limiter). Don't peak-normalize per channel or levels
  pump on every edit.
- **Ticker in `initState`**, never a lazy `late final` (CLAUDE.md — lazy creation
  during `dispose` throws deactivated-ancestor).
- **Separate loop player** from `AudioService`'s SFX player (a feedback blip would
  `stop()` the groove). The Loop Mixer already solved this — copy it.
- **Web audio** is `UrlSource('data:audio/wav;base64,…')`, not `BytesSource`.
- **Dispose** the loop player + stop the groove when the screen closes.
- **Don't start before this doc's own board claim.** The tracker's engine sits on
  `synth.dart`/`loop_engine.dart`; `game_registry.dart`, `core/tuning.dart`, the
  ARBs are hot shared files. `git pull --rebase origin main` before committing,
  keep commits small, update the `docs/PLAN.md` board, push each ship as a
  rebased fast-forward. `dart format` FIRST, whole-project `flutter analyze` LAST.
- **Test harness under load** SIGTERM-flakes on this machine — run tests in small
  batches / per-file; single-file runs and `flutter analyze` are reliable.

---

## 7. Open decisions for the maintainer

- **Instrument sources for v1:** additive-only (cheapest) vs. also ship the sfxr
  generator (recommended — small port, big payoff) vs. also the record→effect
  bridge in v1 (biggest wow, most work).
- **Grid size / channels:** kid default (e.g. 4 ch × 16 steps) and the Studio
  ceiling.
- **How much of the effect chain to port first** (pitch/formant/stretch are the
  voice bridge; distortion/bitcrush/ringmod are the "producer" mangling).
- **Retro skin** (monospace FT2/IT look) as a Studio theme — yes/no.
- **`.mod`/`.xm` import** — worth it as a "play the classics" hook, or out of
  scope? (Substantial parsers; clearly post-v1.)
