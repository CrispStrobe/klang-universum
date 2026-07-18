# The DAW Workshop tool — scoping & architecture

_A separate multi-track Workshop tool that arranges audio from every module
(Song Book, Tracker, Score/Workshop, TAB, DrumKit, direct samples) on a
timeline. Maintainer vision, 2026-07-18._

## The core decision: "vector, not bitmap"

**Question the maintainer raised:** should a clip placed on a DAW track be a
*baked* audio buffer, or should it stay a *live reference* to its source model —
rendered on the fly, so editing the source updates the clip (like a vector
object in a bitmap editor)?

**Answer: the vector model is not only possible, it's the natural fit for us.**
Every module in the app already renders **offline, purely, and deterministically**
to a PCM buffer:

| Module        | Model (the "vector")            | Offline renderer |
|---------------|----------------------------------|------------------|
| Loop Mixer    | `GrooveSpec` / `LoopEngine`      | `renderLoop()` |
| DrumKit       | `DrumRowsPattern`                | `.render(timing)` |
| Tracker       | `TrackerSong`                    | its renderer |
| Score/Workshop| `MultiPartScore` / `Score`       | playback → synth |
| TAB           | `TabDocument` → `Score`          | playback → synth |
| Song Book     | stored MusicXML → `Score`        | playback → synth |
| Samples       | raw PCM                          | (already raster) |

So a clip stores a **reference to its source model** plus placement; the master
render **rasterises each clip on demand and caches it**, keyed so a clip
re-renders only when its source actually changes. Edit a source → its clip
updates; everything else is served from cache.

**The one caveat** — we have **no realtime audio graph** (the app plays by
rendering offline then handing PCM to `audioplayers`/the gapless loop player). So
the DAW is an **offline render-then-play** tool: "Play"/"Export" *bakes* the whole
arrangement to one buffer. The per-clip cache is what keeps that cheap — an edit
re-bakes only the changed clip, not the whole mix.

This also gives non-destructive editing for free (the arrangement stores models,
not audio) and tiny project files.

## The core (SHIPPED — pure, tested)

`lib/core/audio/daw_timeline.dart` (Flutter-free, 6 tests):

- `ClipSource` — the "vector": `render(sampleRate) → PCM` + a `cacheKey` that is
  equal iff the audio is identical. `SampleSource` (raw PCM) is the trivial impl.
- `Clip` = source + `startMs` + `gain` + `muted`; `DawTrack` = a lane of clips
  with its own gain/mute; `DawTimeline` = the arrangement.
- `renderTimeline(timeline, {cache})` — rasterises every audible clip (one render
  per distinct `cacheKey`, via the cache), sums at sample-accurate offsets scaled
  by clip×track gain, and soft-limits (tanh knee) so overlaps don't hard-clip.
  Pass a persistent `cache` so re-baking after an edit only re-renders what moved.

## Next slices (unbuilt)

1. **Per-module `ClipSource` adapters** — thin wrappers that delegate to each
   module's existing offline renderer and expose a `cacheKey` from the model's
   value/version: `GrooveSource(GrooveSpec)`, `DrumSource(DrumRowsPattern)`,
   `TrackerSource(TrackerSong)`, `ScoreSource(MultiPartScore)` (Score→synth),
   `SampleSource` (done). Each is small + unit-testable against its renderer.
2. **"Send to DAW" from each module** — a share action that hands the current
   model to the DAW as a new clip (Song Book / Tracker / Workshop / TAB / DrumKit
   / a recorded sample). Mirrors the existing "Open in Tracker/Workshop" bridges.
3. **The DAW surface** — a tracks×time arrangement view: add/name/gain/mute
   tracks, drag clips in time, per-clip gain/mute, Play (bake+play the loop),
   Export (the shared music/audio export sheet), and **re-open a clip's source**
   for editing (round-trips back through the module, then the clip re-renders).
4. **Mutable takes + merge/convert** (the maintainer's other ask) — record
   several takes onto a track as separate clips; select one/many/all to **merge**
   (sum-and-bake, or keep as a group) and **convert** (a beat-clip → notation via
   `drumParts`, etc.). `loop_record.LoopStack` models the take stack.

## Audience note

The DAW is an **advanced** Workshop tool (like the Tracker), not a first-run kid
game — surfaced from the Workshop shell, not the game grid. Keep the entry simple
(drag clips, press play) with depth available but not required.
