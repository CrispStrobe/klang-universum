# Tracker — GUI, element-handoff & universal I/O idea board

Scope captured from the user (2026-07-18): **(1)** four picked GUI items;
**(2)** hand over "elements we have in other parts of the codebase" — basic⇄
advanced tracker, waveforms generated/modified elsewhere; **(3)** wire **all**
importers/exporters "anywhere they can be of use" (ABC etc.).

This is the written-up plan. It is grounded in two read-only codebase surveys
(import/export inventory + waveform/instrument inventory, 2026-07-18), so every
idea below names the code that already exists to build on. **Nothing here is
committed engine work** — the split with `@tracker-replayer` still holds: I own
the screens (`advanced_tracker_screen.dart`, `tracker_screen.dart`,
`home_screen.dart`, other feature screens) + ARBs + docs + new app-side glue
files; **he owns** `tracker_song.dart` / `tracker_engine.dart` / `mod/*`. Any
idea that needs an engine/model change is tagged **[needs-engine]** and must be
handed to him, not done here.

Ownership legend: **[screen]** mine · **[glue]** new app-side file, mine ·
**[needs-engine]** @tracker-replayer · **[lib-exists]** the codec already exists
in `crisp_notation_core`/`mod/`, only wiring is needed.

---

## A. The four picked GUI items (all [screen])

### A1. Playhead follows song jumps  ★ correctness, unblocked
Today the moving playhead uses linear `elapsed ÷ patternMs` math
(`advanced_tracker_screen.dart` ~L310–319). On any song with `Bxx` position-
jump, `Dxx` pattern-break, or `E6x` pattern-loop — including **many imported
modules** — the highlighted row is wrong during playback.
**Fix (enabler already shipped by @tracker-replayer):** at play-start compute
`final map = resolveTimingMap(_song)` once; each frame
`final e = map[rowIndexAtMs(map, elapsed % _song.songTotalMs)]` →
`_playingOrder = e.orderIndex; _row.value = e.row`. Pure screen change.
*Test:* a 2-pattern flow song (`Dxx` break) — assert the playhead visits the
resolved row sequence, not the linear one.

### A2. Instrument column + instrument list panel  ★ FT2/IT parity, unblocked
The grid has note/vol/fx columns but **no instrument column** — you can't say
"this cell plays instrument 03." @tracker-replayer shipped `TrackerCell.instrument`
(1-based into `TrackerSong.instruments`, a real per-note pool used by imports
too) and said explicitly *"`TrackerSong.instruments` is the pool to expose in the
UI."*
**Build [screen]:** (a) an **instrument column** in the cell (a 2-hex field in
the field-cursor cycle: note → inst → vol → fx); typing digits sets
`cell.instrument`. (b) A **side/overflow instrument-list panel** listing
`_song.instruments` (number · name · type) with select-active, rename, and
"assign the picker instrument to this slot." Writing `cell.instrument` goes
through the existing engine setters — but verify those setters **preserve** the
instrument field (the replayer just fixed `setCellVolume`/`setCellEffect`/
`transposeBlock` dropping fields; the instrument write path must round-trip).
*Blocked only if* a new engine setter for the instrument column is needed →
then **[needs-engine]** a `setCellInstrument`.

### A3. VU meters + on-screen piano  (polish, [screen])
- **Per-channel VU meters:** reuse the existing `_ChannelMeter` idiom; drive
  peak/RMS from the rendered stem (we already cache loop PCM for the scope). A
  cheap version: sample `renderLoopPcm()` per channel at the playhead.
- **On-screen piano keyboard** at the bottom (MilkyTracker/Renoise feel) that
  (a) lights notes as they sound (from the same timing map as A1) and (b) is
  tappable for note entry on touch (reusing the multi-octave piano the Score
  Workshop already ships). Doubles as the touch note-entry surface.

### A4. Load + preview WAV samples  ([screen] + tiny [glue])
Today the sample editor records from mic only. Add:
- **Load a WAV file** into the sample editor: `file_selector` → `wav_io.dart`
  PCM16 reader → `Float64List` → the existing `_sampleFrom` pipeline. (Same
  entry as a recorded clip; the trim/normalize/reverse/stretch/voice-fx chain
  and the `_SampleWaveform` trim handles all just work.)
- **Preview** the (trimmed/edited) sample before assigning: a ▶ button in the
  record sheet that plays the current `_sampleFrom(...)` result once.

---

## B. Element handoff (the "hand over what we have elsewhere" ask)

### B1. Basic ⇄ Advanced tracker carry-over  ★ high value, [screen]
**Finding:** both trackers are built on the **same** `TrackerEngine`. Beginner
(`tracker_screen.dart`) drives a `TrackerEngine _engine` + A–D slot snapshots
(`exportCells()`/`importCells()`); Advanced drives a `TrackerSong` that *wraps* a
`TrackerEngine`, and already `import`s `tracker_screen.dart`. **But both mode
switches start fresh:** `tracker_screen.dart:1263` → `const AdvancedTrackerScreen()`
and `advanced_tracker_screen.dart:1957` → `const TrackerScreen()` carry nothing.
**Build:**
- `AdvancedTrackerScreen({TrackerSong? initialSong})` [screen] — additive param.
- **Beginner → Advanced:** in the mode-switch handler, build a `TrackerSong`
  from `_engine.channels` + each non-empty slot as a pattern (slots → patterns,
  channels → channels). Chromatic/endless is a superset of the pentatonic grid,
  so this is lossless.
- **Advanced → Beginner:** Advanced is a superset (chromatic, N channels, N
  rows). Offer a **best-effort down-map** (first bar, map channels onto the
  Beginner band, snap off-scale notes) with a clear "some detail won't fit"
  notice — or, cleaner, make Advanced→Beginner a *fresh* switch but keep
  Beginner→Advanced the lossless promote path. Decide with the user.
- *Test:* place notes in Beginner, switch, assert the Advanced `noteCount` /
  positions match.

### B2. Free the trapped waveform — sample reuse & a sound library
**Finding:** a recorded/edited sample is **trapped** on one channel: a
`SampleInstrument` with no `toJson`, absent from the `KU1.` token, stripped by
Song-Book/MusicXML/MIDI. The only escape today is the **Basic tracker's `.mod`
export** (embeds PCM via `mod_bridge.dart trackerToMod`).
- **B2a. "Copy sample to another channel / into the picker"** [screen] — a UI
  action calling the existing `setChannelInstrument` with the same instrument.
  No serialization needed; pure reuse. Quick win.
- **B2b. PCM-preserving module export from *Advanced*** — Advanced's module
  export currently goes through the Score path and **drops PCM**; Basic's keeps
  it. Route Advanced module export through the sample-aware `trackerToMod`
  bridge so recorded samples survive. **[needs-engine/glue]** (touches
  `mod_bridge.dart` region) — coordinate with @tracker-replayer.
- **B2c. Serializable sound** **[needs-engine]** — give `SampleInstrument`
  (base64 PCM) / `SfxrInstrument` (`SfxrParams` is all numbers → trivial JSON) a
  `toJson`/`fromJson`, then a per-sound share token or a "Sound Library"
  save-slot store (like the `KU1.` token but for one instrument). This is the
  real backbone of cross-feature sound sharing; propose to @tracker-replayer.
- **B2d. Surface `MultiSampleInstrument`** [screen, latent] — a full XM/IT-style
  multi-zone keymap instrument exists (`multi_sample_instrument.dart`) but is
  **used in no screen**. Expose "build a keymap instrument from N samples" in
  the instrument panel (A2). Latent parity capability, already tested.

### B3. Loop Mixer ⇄ Tracker  ([glue] converter + [screen] wiring)
**Finding:** the Loop Mixer's `GrooveSpec` is fully serializable (`KU1.` token)
and holds `userCells` (sung melody as note cells), `beatRows` (beatboxed drums),
`userInstrument` (an `Instrument` name) — but **no converter to tracker** exists.
- **B3a. Import a groove into the tracker** [glue]: a `grooveSpecToTrackerSong`
  converter (`PatternCell{midis,steps}` → `TrackerCell` runs;
  `beatRows` → a `PercussionInstrument` channel; `userInstrument` → an
  `AdditiveInstrument` channel). Then an **"Open in Tracker" / "Paste KU1 token"**
  action in the Advanced tracker. Turns a sung+beatboxed groove into an editable
  pattern — a marquee handoff.
- **B3b. Export a tracker pattern as a groove** (nice-to-have) — the reverse, so
  a tracker beat can seed the Loop Mixer's jam mode.

---

## C. Wire ALL importers/exporters everywhere useful

**Finding (matrix):** the library has an enormous codec set; most is wired **only
in the Score Workshop**. The trackers, Loop Mixer, Song Book, My Melody and Free
Sing each expose a thin, inconsistent subset. ABC is the flagship example — a
full reader *and* writer exist (`scoreFromAbc`/`multiPartScoreFromAbc` +
`scoreToAbc`/`multiPartToAbc`) but are wired **only** in Workshop (both) and Song
Book (import paste).

### C0. The systematic fix — a shared `MusicIoMenu` component  ★ [glue]
Stop copy-pasting per-screen I/O. Build **one** reusable widget:
`MusicIoMenu({ required Future<MultiPartDocument> Function() read, required void
Function(MultiPartDocument) write, Set<IoCap> caps })` that offers every codec
the screen opts into (import + export), handling file pick / paste / save
uniformly. Every music screen mounts it with a `read`/`write` adapter. This is
what makes "wired anywhere it can be of use" true and maintainable instead of a
scatter of one-off menu items. All codecs it calls **[lib-exists]**.

Then the concrete coverage gaps it closes:

### C1. ABC everywhere  ★ user-called-out, [lib-exists]
Add ABC **import + export** to: Advanced Tracker, Beginner Tracker, Loop Mixer,
My Melody, Free Sing. All already have a `Score`/MusicXML path;
`module_notation.dart:586` even defines an unused `TextNotation.abc` branch.
Near one-liners via the shared menu (C0).

### C2. Beginner Tracker — add XM/S3M/IT export  [lib-exists]
Beginner exports **MOD only** though `writeXm/writeS3m/writeIt` + `convertDocTo`
exist (Advanced already exposes all four). Add the format picker.

### C3. Advanced Tracker — broaden import  [lib-exists]
Advanced imports MusicXML/MIDI only. Add ABC / MEI / Humdrum `.krn` / MuseScore
`.mscx/.mscz` / Guitar Pro `.gp/.gpx` import (the multi-part readers exist and
Workshop already uses them).

### C4. Advanced Tracker — broaden notation export  [lib-exists]
Beyond MIDI/MusicXML/module, add: ABC, MEI, kern, LilyPond, `.mxl`, **PDF**
(`score_pdf.dart`), SVG, PNG, Braille, MuseScore `.mscx`. Via C0 these are free.

### C5. Loop Mixer — notation import + module export  [lib-exists]
Loop Mixer exports MusicXML but can't **import** notation, and can't emit a
module. Add notation import (seed a groove from a Score) and module export
(`multiPartToModuleDoc`→`convertDocTo`).

### C6. My Melody / Free Sing — real export menu  [lib-exists]
Both only "Save to Song Book" (MusicXML). Give them the full export menu
(ABC/MIDI/MusicXML/module/PDF) via C0.

### C7. Song Book — export UI  [lib-exists]
Song Book is import-only; a stored `ImportedSong` is MusicXML → `Score`. Add an
**export** action so any saved song can be re-emitted to any format (ABC, MIDI,
LilyPond, PDF, module…). High leverage: the Song Book becomes the app's format
hub.

### C8. Module ⇄ notation text bridges  [lib-exists]
`moduleToMusicXml` / `moduleToTextNotation` / `scoreFromTextNotation`
(`module_notation.dart`) are library-only (only the `bin/*.dart` CLIs call
them). Surface "convert a module to notation" (and back) — e.g. import a `.mod`
straight to the Score Workshop, or export a tracker song as LilyPond via the
module path.

### C9. Long-tail codecs  [lib-exists]
`asciiTabToScore` (ASCII-tab **import**) is wired in **no** screen — add to
Workshop import. `scoreToGpif` (Guitar Pro **text** export) exists but no screen
writes GP — add to Workshop export (note: no binary `.gp` writer exists, GPIF
text only).

---

## D. Suggested execution order (slices, each its own commit, checkpointed)

1. **A1 playhead-follows-jumps** — small, correctness, unblocked. *(do first)*
2. **C0 `MusicIoMenu` + C1 ABC in the trackers** — the systematic win; ABC is
   the user's flagship. Land the shared component with tracker ABC/module/score
   I/O routed through it, then fan out.
3. **A4 load+preview WAV** + **B2a copy-sample-to-channel** — small [screen]
   reuse wins.
4. **B1 Basic⇄Advanced carry-over** — needs one product decision (Adv→Beg
   down-map vs fresh); ask the user.
5. **A2 instrument column + list** — bigger; verify/【maybe】needs a
   `setCellInstrument` engine setter (coordinate).
6. **C2–C9 I/O fan-out** — once C0 exists, each screen is a small adapter:
   Beginner XM/S3M/IT (C2), Advanced broad import/export (C3/C4), Loop Mixer
   (C5), My Melody/Free Sing (C6), Song Book export (C7), module↔text (C8),
   long-tail (C9).
7. **B3 Loop Mixer→Tracker groove import** — the marquee cross-feature handoff.
8. **A3 VU meters + on-screen piano** — polish.
9. **[needs-engine] hand-offs to @tracker-replayer:** B2b PCM-preserving Advanced
   module export, B2c serializable sound + share token, B2d MultiSample surfacing
   (screen part mine, engine part his). File these on the board for him.

## E. Coordination
- Every slice: update the 🚧 board + `git pull --rebase origin main` + push
  before touching a hot shared file (`composition_workshop_screen.dart`,
  `loop_mixer_screen.dart`, `import_screen.dart`, `home_screen.dart`,
  `tracker_screen.dart`, the ARBs) and after each ship.
- **Do not edit** `tracker_song.dart` / `tracker_engine.dart` / `mod/*` — those
  are @tracker-replayer's; the **[needs-engine]** items are proposed to him, not
  done here.
- Shared new glue files (`MusicIoMenu`, `grooveSpecToTrackerSong`) are mine to
  create under `lib/features/...`/`lib/core/audio/` app-side.
