# Sound Library browser — UI contract for @tracker-ui

**Owner of the UI:** @tracker-ui (you own the tracker screens; the tracker-replayer
agent will NOT touch them). **Owner of the engine APIs below:** @tracker-replayer
(all shipped + tested on `main` — this is a stable contract, not a moving target).

Goal: a **Song Book-style sound-library browser** in the Advanced Tracker —
browse the built-in voices by family, **audition** one, and **drop it into an
instrument slot** (the same `TrackerSong.instruments` pool the instrument panel
already exposes). No engine work is needed; this is a screen + wiring job.

## The engine surface (all in `lib/core/audio/`, stable)

### 1. Built-in procedural voices — `tracker_engine.dart`
- `kTrackerInstruments : List<InstrumentOption>` — the 20 sample-free voices
  (4 additive, 7 sfxr, 3 Karplus plucked, 3 FM, 3 subtractive).
- `InstrumentOption { String id; TrackerInstrument Function() build; SoundCategory get category; }`
  — `build()` is cheap (no synthesis until `renderChannel`).
- `soundLibraryByCategory() : Map<SoundCategory, List<InstrumentOption>>` — the
  entries grouped for the browser. Iterate `SoundCategory.values` for section order.
- `enum SoundCategory { tonal, plucked, chiptune, drum, recorded }` +
  `soundCategoryOf(TrackerInstrument)` (classify a built instrument).

### 2. Bundled CC0 samples — `sound_library.dart`
- `kBundledPercussion : List<BundledSampleInfo>` — the VCSL CC0 one-shots.
- `BundledSampleInfo { id, assetPath, category, baseMidi }`.
- Build one (app reads the asset bytes first):
  ```dart
  final data = await rootBundle.load(info.assetPath);
  final inst = bundledSampleInstrument(info, data.buffer.asUint8List());
  ```
  `assets/sounds/percussion/` is already registered in `pubspec.yaml`.

### 3. SoundFont (GM) instruments — `sf2/sf2.dart` + `sf2/sf2_remote.dart`
- Parse (bytes already in hand): `Sf2SoundFont.parse(bytes)` →
  `.presets : List<Sf2Preset>` (each `{name, bank, program, zones}`) and
  `.samples`.
- Build a playable key-split voice: `sf2InstrumentFromPreset(sf, preset, id: '…')`
  → `Sf2Instrument` (a `TrackerInstrument`).
- On-demand download (avoids bundling ~140 MB):
  ```dart
  final sf = await downloadSoundFont(kFluidR3Gm, fetch: myHttpGet, cache: myCache);
  ```
  - `fetch` = `Future<Uint8List> Function(Uri)` — back with `http` (you already
    added `http` for the score library).
  - `cache` = implement `SoundFontCache` with `path_provider` (read/write by id).
  - The permissive-license gate runs BEFORE fetching; confirm the ~140 MB size
    with the user first (`kFluidR3Gm.approxBytes`). Show `kFluidR3Gm.attribution`
    in the Sources & credits screen (MIT).

## Audition + assign (both already have hooks you built)

- **Audition:** build the instrument and render a short preview note, then play it
  on your existing sample-preview loop player (the `_samplePreview` you added for
  "A4 load+preview WAV"):
  ```dart
  final buf = inst.renderChannel(
    [const TrackerCell(midi: 60), TrackerCell.empty, TrackerCell.empty, TrackerCell.empty],
    const TrackerTiming(rows: 4, stepsPerBeat: 2),
  ); // Float64List → your preview player
  ```
- **Assign to a slot:** add the built instrument to the song's pool and point the
  channel/active instrument at it — reuse the paths you already have
  (`setChannelInstrument` / the instrument panel's `TrackerSong.instruments` +
  `TrackerCell.instrument` / `copyInstrument`). A bundled/SF2 instrument is just a
  `TrackerInstrument`, so it drops into the pool like any other.

## Suggested UX
- A "Sound Library" sheet reached from the instrument panel (📚 next to the
  existing pool list). Sections = `SoundCategory` (Tonal / Plucked / Chiptune /
  Drum / Recorded). Each row: name + ▶ audition + "Use" (assigns to the active
  channel/slot).
- A "Download GM soundfont" row under Recorded/Drum that runs the on-demand
  fetch (size-confirm dialog), then lists its presets to pick from.

## Acceptance (your tests, screen-side)
- The browser lists every `SoundCategory` that has entries and every
  `kTrackerInstruments` id appears exactly once.
- Auditioning a voice renders non-silent audio (no device needed — assert the
  preview buffer is non-zero).
- "Use" puts the chosen instrument into `TrackerSong.instruments` and a placed
  note carries its `TrackerCell.instrument`.
- (If you wire SF2 download) a fake `ByteFetcher` returning a fixture soundfont
  yields pickable presets — see `test/sf2_remote_test.dart` for the pattern.

## "Load SoundFont" — READY TO WIRE (shipped by @tracker-replayer, `58aa85d`)

The whole "load a `.sf2`/`.sf3` file → browse presets → pick a GM voice" flow is
already built as a **self-contained, value-returning sheet** (mirrors
`showSampleLibrarySheet`). You add it with **one line** — no parse/decode/browse
code on your side:

```dart
import 'package:comet_beat/features/library/soundfont_sheet.dart';

final inst = await showSoundFontSheet(context); // Future<TrackerInstrument?>
if (inst != null) {
  setState(() => _song.instruments.add(inst)); // drop into the pool
  // …then point the active instrument / channel at it as you already do.
}
```

- Handles `.sf2` directly and `.sf3` via the platform glint Vorbis decoder
  (auto-selected); a compressed font on a platform with no decoder shows a
  friendly in-sheet error (mentions `.sf2`) rather than failing.
- File pick is `file_selector` (`.sf2`/`.sf3`); audition renders middle C through
  the ambient `AudioService` (a no-op if none is provided).
- Returns the full **key/velocity-split** GM voice as a plain `TrackerInstrument`,
  so it drops into `TrackerSong.instruments` like any other sound.
- **Headless facade** (if you want to skip the sheet UI):
  `lib/core/audio/sf2/soundfont_loader.dart` — `loadSoundFont(bytes)` →
  `LoadedSoundFont` (`.presets`), `soundFontInstrument(loaded, preset)`,
  `soundFontPresetLabel(preset)`.
- **l10n:** the sheet ships English literals; localize its strings when you wire
  it (that's the only thing left, and it's screen-side/yours).
- Tests: `test/soundfont_loader_test.dart` (facade + real-font dev check) and
  `test/soundfont_sheet_test.dart` (widget flow) are the pattern.

## Coordination
- **HANDS OFF** `tracker_engine.dart` / `tracker_song.dart` / `sf2/*` /
  `sound_library*.dart` / `soundfont_loader.dart` — those are @tracker-replayer's;
  the APIs above are frozen. `features/library/soundfont_sheet.dart` is yours to
  localize/restyle when you wire it.
- Claim the browser on the PLAN board before you touch the tracker screens, as usual.
