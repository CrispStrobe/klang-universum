# Workshop → editor parity — conceptual directions

Companion to [WORKSHOP_PLAN.md](WORKSHOP_PLAN.md) (the phase log, G1–G7). That
file records *what we built*. This one asks *why the remaining gaps exist* and
argues an order of attack. Ideas and directions — not a task list yet.

Convention (unchanged): we do **not** name or allude to other products anywhere
in code or docs, and we never frame the design as matching anyone. Interchange
**formats** are named only by their standard name / file extension. Below,
"the desktop reference class" means full-featured notation programs generically.

---

## The finding: 28 missing features, but far fewer real causes

A full inventory of the editor (2026-07-16) listed ~28 things the desktop
reference class has that we lack. Read as a list, that's a multi-year backlog.
Read causally, it collapses. **Four root causes explain almost all of it**, and
three of them are ours, not the renderer's.

The most important context for everything below:

> **`crisp_notation` already models nearly everything we're "missing".**
> `TupletSpan`, `Measure.voice2`, `keyChange`/`timeChange`/`clefChange`/
> `tempoChange` per measure, `startRepeat`/`endRepeat`/`volta`/navigation marks,
> grace notes, ornaments, notehead shapes, arpeggio, tremolo, ottavas, pedals,
> chord symbols, figured bass, annotations — all public, all engraved, all
> round-tripping through MusicXML.

We are not blocked on the library. We are blocked on **our own document model**,
which cannot *express* what the renderer can already *draw*. That reframes the
work from "build a notation program" to "stop throwing away what we already
have."

### Cause 1 — measures are derived, not real *(the load-bearing one)*

`ScoreDocument` is a **flat `List<EditorElement>` per part**; bars only come into
existence in `_packMeasures`, which greedily fills them at build time
(`score_document.dart:874`). A bar has no identity — it's a transient artifact of
packing. Everything that needs to *point at a bar* is therefore impossible:

| Missing feature | Why it's actually blocked |
|---|---|
| Mid-score key / time / clef / tempo changes | Nowhere stable to anchor a change; bar indices shift when you edit note 1 |
| Repeats, voltas, D.C./D.S./coda, barline styles | Same — they're bar-anchored properties |
| Insert / append / delete bar | Bars aren't objects, so they can't be operated on |
| Notes splitting + tying across barlines | The packer short-fills instead (`:811`) — a known silent wrong |
| Tuplets | A rhythmic container the flat packer can't express |
| Voices 2–4 | The packer assumes exactly one stream |
| Time sig limited to 2/4, 3/4, 4/4; key to ±4 fifths | Document-level singletons, so the pickers stay tiny |

That's **7 of the 28**, one cause. It also drives a second cluster: because
position is a *list index*, selection is an index range — which is why selection
can't be discontiguous and can't cross parts, and why the clipboard is per-part.

**Direction.** Promote the bar to a first-class object and make position a
**musical address `(bar, voice, tick)`** instead of a list index. Concretely:
a measure spine of `Bar` objects, each holding per-voice element lists, each with
a stable id. Selection becomes a **set of element ids**; the caret becomes an
address, not "after element *i*". This is the single highest-leverage change in
the whole document — it doesn't add features so much as *stop preventing* them,
and it maps 1:1 onto the `Measure` the renderer already wants.

Sequencing note: this is a real refactor (23 widget tests + a snapshot-based undo
stack ride on the flat list), so it wants its own phase and its own worktree —
but it should come **before** the feature work it unblocks, not after, or we pay
for each feature twice.

### Cause 2 — the editor has no modes

There is no note-input mode. The staff is *always* live for placement, so there's
no safe pointer state for navigating or inspecting (marquee-mode is the
workaround). Worse, the value strip is **dual-purpose**: picking a duration both
arms the next note *and* retroactively rewrites the selection (`_pickValue:850`).
The reference class universally separates two states — *input* (caret advances,
typing enters notes) and *select/object* (clicking selects, palettes apply to the
selection). That separation is what makes keyboard-first entry possible at all.

**Direction.** An explicit input-mode state machine, with the caret as a musical
address (Cause 1 pays for this). Mode is always visible in the status line. This
is what turns the existing shortcut set (A–G, 1–5, R) from a convenience into an
actual entry method — you can't do fluent keyboard entry while every click is a
note placement.

### Cause 3 — depth has nowhere to live

Every property lives in one `⌃` popup that only appears for a **single**-note
selection. That's why the last 15 element types have no UI: there's no surface to
put them on, and nobody wants toolbar button #40. Note the shape of this problem
— it's not 15 features, it's one missing surface.

**Direction.** A **selection-driven inspector** (a panel/sheet reflecting whatever
is selected). It scales to arbitrary element types at ~zero marginal UI cost, and
it's the standard answer in the reference class for exactly this reason. Pair it
with categorized palettes for *insertion* (dynamics, lines, repeats, text), the
inspector for *modification*.

### Cause 4 — the canvas defeats a renderer that's already correct

The lag is **not** the engine, and (after `22f9e5f`) it is **not** single-part.
`crisp_notation` carefully routes every interactive setter — `ghostTarget`,
`caret`, `highlightedIds`, `suppressElementIds` — to `markNeedsPaint`, and
early-returns on a value-equal document. Single-part hover therefore costs **zero
layouts**, correctly. Multi-part costs **~4 full layouts per rebuild, across 2
frames**, because our canvas defeats each guard in turn:

1. **A fresh `Future` every build.** `multi_part_canvas.dart:108` passes
   `MusicFonts.load(...)` inline to `FutureBuilder`; `music_font.dart:110`
   returns `Future.value(cached)` — a **new instance** each call, never `==`. So
   `FutureBuilder` resubscribes and rebuilds a second time, on a second frame.
   The snapshot is then **ignored** (`builder: (context, _)`) — it reads
   `metadataOrNull` instead. This buys nothing and doubles everything.
2. **`PageMetrics` has no `==`.** `page_layout.dart:12` declares no
   `operator ==`, so the fresh instance at `multi_part_canvas.dart:122` fails the
   render object's identity guard → `markNeedsLayout()` on *every* build, even a
   pure hover. This also makes the deep `MultiPartScore ==` walk pure waste: it
   correctly concludes "equal, skip relayout", and then `metrics` forces the
   relayout anyway.
3. **A discarded probe layout.** `multi_part_canvas.dart:190` runs a full
   `layoutMultiPartPages` and throws away everything but one height double.
4. **`buildMultiPart()` is the one un-memoized builder** — its `ScoreDocument`
   sibling has `_scoreCache`/`_invalidate` (`score_document.dart:205`);
   `MultiPartDocument` has no equivalent, so it re-allocates every `Measure` and
   element per call (`multi_part_document.dart:173`).
5. **`_onMpDragUpdate` was missed by `22f9e5f`** (`:511`) — it `setState`s
   unconditionally, so multi-part note-drag costs ~4 full layouts *per pixel*.
   Its single-part twin `_onElementDragUpdate:802` is correctly guarded.

**Direction.** The fix is to *stop calling layout*, not to make layout faster —
1, 2, 4, 5 are each a handful of lines and together should take multi-part hover
from ~4 layouts per tick to **zero**. Then decouple the canvas from screen-level
`setState` (a `ValueNotifier` for hover/caret + a `ValueListenableBuilder` around
the canvas only) so pointer traffic can't rebuild the parts strip and input bar.

**The remaining ceiling is a genuine library ask.** `crisp_notation` has **no
incremental layout**: one keystroke in bar 400 of a 12-part score re-engraves all
parts × all measures × 2–3 passes (`multi_system.dart:99-140`, `:412`). Fixes
1–5 make our *interaction* free; they don't make a large *edit* cheap. A
dirty-measure-range API (or reusing the "natural" pass across edits) is the
scaling story for big scores — worth opening as a contract, but **only after**
1–5, because right now we'd be optimizing an engine we're calling 4× more than
we need to.

---

## The thing that isn't on the feature list: we can't round-trip our own saves

Worth separating out, because it reads as a papercut and isn't. `Save` writes
MusicXML into the Song Book (`_save:1431`), but `loadScore` is **lossy by
construction**: voice 1 only, **chord → first pitch only**, ties and
articulations dropped (`score_document.dart:747`, `:765`).

So **save → reopen silently destroys the user's work.** There is no native
document format and no lossless round-trip. Before any parity feature: a score
editor you can't reliably save and reopen isn't one, and every feature we add
above this line inherits the data loss. Cheap-ish, and it's the credibility
floor.

(Adjacent, same theme: only MusicXML/`.mxl` export all parts — every other
format silently exports the **active part only** (`_generateExport:1157`). Same
class of quiet wrong. The multi-part *readers* all exist in the library; only
MusicXML has a multi-part *writer* — so this one is partly a library ask.)

---

## The strategic tension worth naming

This is a music-education app for ages 6+. **Parity with the desktop reference
class is the wrong goal if it's read as parity of *surface*.** A kid opening the
Workshop should not meet an inspector, a mode switch, and a 40-button palette.

The goal is **capability parity with progressive disclosure** — already the
stated intent in WORKSHOP_PLAN.md ("simple by default … yet scales"), but the
architecture is what makes it honest. Two shelves on one document:

- **Sandbox** — today's surface, ~unchanged. Glyph strip + piano. No modes.
- **Studio** — inspector, input modes, palettes, page view, full meters/keys.

One document model, one renderer, two densities. This is also the *reason* Causes
1–3 are worth paying for: a first-class measure spine and an inspector are
invisible to the kid surface and load-bearing for the other one. Feature work
that can't hide itself behind a shelf toggle should be viewed with suspicion.

---

## Suggested order of attack

Ordered by *unblocking*, not by size.

- **A · Make it fast** — Cause 4, fixes 1–5. Days. Do first: it's cheap, it's the
  user's actual complaint, and every later phase is nicer to build and demo on a
  canvas that doesn't stutter. No model risk.
- **B · Make it trustworthy** — native format + lossless load; multi-part export
  honesty. Stops the bleeding before we add more to bleed.
- **C · Make the document real** — Cause 1: measure spine, `(bar, voice, tick)`
  addressing, id-set selection. The unlock. Big, its own worktree, needs the undo
  stack rethought (snapshot → command model) and probably lifts undo from
  per-part to global while we're in there (today, deleting an instrument is
  simply unrecoverable — `multi_part_document.dart:268`).
- **D · Cash in the unlock** — tuplets, voice 2, mid-score key/time/clef/tempo,
  repeats/voltas, measure ops, cross-bar splitting, full meters and keys. Each is
  now small, and each is mostly *wiring to a renderer that already draws it*.
- **E · Make entry professional** — Causes 2+3: input modes, keyboard-first
  entry, the inspector, palettes. Rides on C's caret.
- **F · Make it sound** — playback is currently a fixed-tempo, rest-less,
  chord-less, active-part-only beep sequence (`_play:955`), which is odd given
  the library ships `playbackTimeline` / `soundingAt` / `TempoMap` and the app
  already owns audio. Real transport + moving cursor + per-part mute is mostly
  wiring, and it's disproportionately motivating for the target user.
- **G · Scale** — the incremental-layout contract, the 256-note cap, page/print
  view, PDF. Only meaningful once A–F land.

**A and B are independent of everything and should start now. C is the fork in
the road** — every feature in D built *before* C gets built twice.

---

## Open questions for the maintainer

1. **Is Studio actually wanted?** The whole argument above assumes we want
   capability parity at all. A defensible alternative: cap the Workshop at
   "excellent kid sandbox", and treat interchange export as the escape hatch to a
   real desktop program. That would make C–E unnecessary and A–B + F sufficient.
   This is the highest-value decision here and it's not ours.
2. **Where does the notation depth get taught?** If Studio exists, it's a second
   product surface with its own learnability burden — does it get primers /
   tutorials like the games do?
3. **How big is a realistic score?** The incremental-layout ask (G) is only worth
   opening if people write 30+ bars × 4+ parts. If real use is 8 bars × 2 parts,
   fixes A1–A5 end the performance story permanently.
</content>
