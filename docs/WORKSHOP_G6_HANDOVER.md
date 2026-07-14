# Handover — G6: multi-instrument authoring in the Composition Workshop

**Your mission:** turn the single-part Composition Workshop into a
**multi-instrument score editor** — edit several parts (e.g. flute + piano, or an
SATB choir), lay them out as a real full score, and import/export multi-part
files. This was the Workshop's last big deferred feature (P4/G6), blocked only on
a public multi-part model. **That blocker is now gone:** partitura shipped
`MultiPartScore` + `MultiPartView` and **both are exported from the public
barrel**, so mus and CI can use them. No partitura ask is required for the core
of this — build on the public API.

Work in a **feature branch + a worktree that is a sibling of `mus/`** (so the
`../partitura-public/...` path dep resolves — a worktree under `.claude/` breaks
it). Keep `origin/main` green. **`lib/features/workshop/**` is a HOT file set** —
another agent (`workshop→games` on the board) ships there; `git pull --rebase`
often, keep commits small, and update the `docs/PLAN.md` 🚧 board at every
checkpoint.

---

## What already exists (your starting point — don't rebuild it)

The whole Workshop is just **two source files** + four tests:

- **`lib/features/workshop/model/score_document.dart`** — `ScoreDocument`: a rich
  **single-part** editable document (an ordered `List<EditorElement>` → an
  immutable partitura `Score`). It already has everything you need *per part*:
  - Metadata fields: `clef` (`Clef`), `timeSignature` (`TimeSignature`),
    `keySignature` (`KeySignature`).
  - Build outputs: **`Score buildScore()`** and **`GrandStaff buildGrandStaff()`**.
  - Editing commands: insert-at-caret, `transposeSelected`, `setDurationOfSelected`,
    accidentals, `toggleArticulationOfSelected`, ties, slurs, hairpins, dynamics,
    rests/dots, `moveById(id, StaffTarget, {clef})`, copy/cut/paste.
  - Selection + caret (`selectIndex`, `selectNext/Prev`, `extendLeft/Right`,
    `selectedIds`, range ops), multi-level **undo/redo** (`undo`, `redo`,
    `canUndo`, `canRedo`), and **`loadScore(Score)`** (flattens voice 1 into
    editable elements; undoable).
  - It is a plain `ChangeNotifier`-style model (no Flutter deps beyond partitura
    types) — unit-tested in `test/score_document_test.dart` +
    `score_document_more_test.dart`.
- **`lib/features/workshop/screens/composition_workshop_screen.dart`** — the
  editor UI. One `ScoreDocument _doc`. Renders the canvas with:
  - **`MultiSystemView(score: _doc.buildScore(), …)`** (the normal multiline
    single-staff view), or
  - **`InteractiveGrandStaffView(grandStaff: _doc.buildGrandStaff())`** (grand
    staff mode) — this is the one with live ghost-note/drag/`suppressElementIds`/
    `dragPreviewOpacity` (C10a/b, already wired by the workshop→games agent).
  - Exports: `scoreToMusicXml`, `scoreToAbc`, `exportGrandStaffToSvg/Png`,
    `exportScoreToSvg/Png`.
  - Two-row touch chrome (clef/time/key/zoom dropdowns + value/accidental strip),
    palettes (dynamics/articulations/ties), ⋮ menu with open-file (MusicXML/MIDI).
- Tests: `composition_workshop_test.dart`, `score_document_test.dart`,
  `score_document_more_test.dart`, `workshop_drop_slot_test.dart`.

**Everything landed contract-wise:** partitura contracts **C1–C10 are all landed
and wired** (staff-tap, hover/caret, drag-to-move, marquee, interactive grand
staff, region controller, export helpers, live drag). See
`docs/WORKSHOP_PARTITURA_CONTRACTS.md` and `docs/WORKSHOP_PLAN.md`.

---

## The partitura APIs you'll build G6 on (all public @main)

Verified exported from the public barrels (`partitura.dart` /
`partitura_core.dart`) as of 2026-07-14:

- **`MultiPartScore`** (`partitura_core/src/layout/multi_part.dart`):
  ```dart
  const MultiPartScore(
    List<Score> parts, {                 // top to bottom, ≥1
    List<StaffBracket> brackets = const [],
    List<BarlineGroup> barlineGroups = const [], // empty = barlines connect through all parts
  });
  factory MultiPartScore.fromStaffSystem(StaffSystem system); // bridges importers → paginating doc
  int get measureCount;                  // from parts.first
  List<BarlineGroup> get effectiveBarlineGroups;
  ```
- **`StaffBracket(int first, int last, StaffBracketKind kind)`** — `kind` is
  `StaffBracketKind.brace` (`{`, one instrument on multiple staves — piano) or
  `.bracket` (`[`, a section — strings). `BarlineGroup(first, last)` = a
  contiguous part-index run whose barlines connect.
- **`MultiPartView`** (`partitura/src/rendering/multi_part_view.dart`) — the
  render widget (a `LeafRenderObjectWidget`):
  ```dart
  const MultiPartView({
    required MultiPartScore document,
    required PageMetrics metrics,        // from partitura_core/src/layout/page_layout.dart
    PartituraTheme theme = PartituraTheme.standard,   // ← pass kidsScoreTheme instead!
    double staffSpace = 8, staffGap = 4, systemGap = 10,
    bool justifyVertically = true, hideEmptyStaves = false,
    int pageIndex = 0, bool drawPageBorder = false,
    void Function(String elementId)? onElementTap,    // tap-to-select any part's element
  });
  ```
  Its render object exposes **`String? elementIdAt(Offset local)`** for
  hit-testing across parts, and drives `onElementTap`. Pagination helpers:
  **`layoutMultiPartPages(...)` → `MultiPartPagedLayout.pages`** (each a
  `MultiPartPageLayout`).

### The one design constraint to know up front
`MultiPartView` today is **render + tap-select + hit-test** — it does **not**
expose the full interactive ghost-note/drag entry that single-part
`InteractiveStaff` / `InteractiveGrandStaffView` do. So don't plan to do *rich*
note entry directly on `MultiPartView`. Use the two-view approach below (edit the
active part with the existing interactive pipeline; `MultiPartView` is the
full-score layout + selection surface). Full in-place multi-part interaction
would be a *new* partitura ask (a "C11") — out of scope; note it, don't block on
it.

---

## Recommended architecture (reuses the single-part editor wholesale)

Add a thin container; **do not** rewrite `ScoreDocument`.

```dart
// lib/features/workshop/model/multi_part_document.dart  (NEW)
class MultiPartDocument extends ChangeNotifier {
  final List<ScoreDocument> parts;   // one per instrument; each keeps its own undo/redo
  int active = 0;                    // the part the toolbar edits
  List<StaffBracket> brackets;       // e.g. a brace over a 2-staff piano
  List<BarlineGroup> barlineGroups;  // usually empty (connect all)

  ScoreDocument get activePart => parts[active];
  MultiPartScore buildMultiPart() =>
      MultiPartScore(parts.map((p) => p.buildScore()).toList(),
                     brackets: brackets, barlineGroups: barlineGroups);
  void addPart({Clef clef = Clef.treble}) { … notifyListeners(); }
  void removePart(int i) { … }        // keep ≥1
  void setActive(int i) { … }
  // measure/metadata consistency helpers (see gotchas: parts should share
  // time signature + measure count for a valid system).
}
```

**Editing:** the toolbar and all commands keep operating on
`document.activePart` (an unchanged `ScoreDocument`). Undo/redo stays **per
part** for v1 (simplest, correct); a global undo stack across parts is a later
polish.

**Rendering (two-view):**
- The **full-score canvas** is `MultiPartView(document: doc.buildMultiPart(),
  metrics: …, theme: kidsScoreTheme, onElementTap: (id) => selectAcrossParts(id))`.
  `onElementTap` → find which part owns `id`, `setActive(thatPart)`, select the
  element in that part. Highlight the active part (tint / bracket emphasis).
- **Active-part editing** happens through the existing `InteractiveGrandStaffView`/
  `MultiSystemView` path *for the active part only* if you want live ghost/drag —
  or, simpler for v1, do note entry via the existing piano/keyboard/caret
  toolchain and let `MultiPartView` reflect it on rebuild. Start simple: tap on
  `MultiPartView` selects; the bottom dock edits the active part; rebuild.

**Per-part instrument setup:** each `ScoreDocument` already carries `clef`; add a
tiny instrument table (name + default clef + `Tuning`/transposition). Transposing
instruments reuse partitura's `transposeBy` (already used by the Concert Pitch
game). Brackets: a piano part = two `ScoreDocument`s (RH treble + LH bass) under
one `StaffBracket(kind: brace)`.

---

## Phases (each ends mergeable, CI-green)

- **P4a — model.** `MultiPartDocument` + tests (`test/multi_part_document_test.dart`,
  mirror `score_document_test`): add/remove/reorder parts, active switching,
  `buildMultiPart()` yields a valid `MultiPartScore` (measure counts line up).
  No UI. Cheap, safe, no hot-file churn beyond the new model file.
- **P4b — render + select.** Swap the workshop canvas to `MultiPartView` when
  `parts.length > 1` (keep the single-part path for one part). Wire `onElementTap`
  → select/switch active part; highlight the active part. Widget smoke test
  (use `pumpGame`/`useGameSurface`).
- **P4c — instrument picker + per-part clef/transposition + brackets.** A "+
  Add instrument" control, a small instrument table, per-part clef dropdown,
  brace/bracket for grouped staves. Transposing-instrument display via
  `transposeBy`.
- **P4d — multi-part I/O.** Import: `MultiPartScore.fromStaffSystem(
  staffSystemFromMusicXml/​Mei/​Abc(...))` → seed the document (each part → one
  `ScoreDocument.loadScore`). Export every part (multi-part MusicXML; the
  partitura CLI already renders multi-part PNG/SVG — reuse its layout).
- **P4e — stretch (needs partitura).** In-place interactive editing directly on
  `MultiPartView` (cross-part ghost/drag). File a partitura contract if wanted;
  don't block P4a–d on it.

---

## Gotchas & discipline (heed these)

- **Hot files / coordination.** `lib/features/workshop/**`, `game_registry.dart`,
  the ARBs are edited by parallel agents. Update the `docs/PLAN.md` 🚧 board
  **before** touching workshop files and after each ship; `git pull --rebase
  origin main` often. The **workshop→games** agent is the other owner here —
  coordinate.
- **CI = public partitura.** mus CI/deploy resolve `../partitura-public`
  (`CrispStrobe/partitura@main`). Every partitura symbol you use **must be on
  public `@main`** — `MultiPartScore`/`MultiPartView`/`StaffBracket`/`BarlineGroup`/
  `PageMetrics`/`layoutMultiPartPages` all are (verified). If you reach for
  something new, grep the public barrel first. (memory: `partitura-public-vs-private-ci`.)
- **Use `kidsScoreTheme`,** not `PartituraTheme.standard`/`.kids`, for every
  StaffView/MultiPartView so the Settings "Handwritten notes" (Petaluma) toggle
  reaches the editor. It's in `shared/score_theme.dart`.
- **Surface-flake on CI:** staff-based widget tests must call
  `await useGameSurface(tester);` (or `pumpGame`) first — CI's 800×600 surface
  throws `getElementPoint`/`_getElementPoint` on off-screen targets (board's ✅
  note; `test/support/game_test_support.dart`).
- **Tickers:** create any `AnimationController`/`Ticker` in `initState`, never a
  lazy `late final` (lazy creation during `dispose` throws deactivated-ancestor).
- **Pre-commit:** `dart format .` **FIRST**, then `flutter analyze` (whole
  project incl `test/`) **LAST** — format can introduce trailing-comma lints, and
  the dart-3.12 formatter fights `require_trailing_commas` on single-element
  multiline collections (prefer a builder/helper over inline one-element lists;
  see how `primers.dart` was refactored). Run `flutter test` **plainly** (the
  `env -u GEM_HOME …` wrapper is only for `pod`/`xcodebuild`/`flutter build`).
- **Fresh worktree:** run `flutter pub get` **before** `dart format` — an
  unresolved-package format run corrupts the whole tree.
- **Apple/desktop builds** on this Mac need the GEM-env wrapper (see `CLAUDE.md`);
  web build needs no pods (`flutter build web`).

## Files to read first
1. `lib/features/workshop/model/score_document.dart` (the per-part engine).
2. `lib/features/workshop/screens/composition_workshop_screen.dart` (how the
   canvas + toolbar are wired; find the `MultiSystemView` / `InteractiveGrandStaffView`
   render sites).
3. `../partitura-public/packages/partitura_core/lib/src/layout/multi_part.dart`
   and `.../partitura/lib/src/rendering/multi_part_view.dart` (the target API).
4. `docs/WORKSHOP_PLAN.md` (G6 section + status) and
   `docs/WORKSHOP_PARTITURA_CONTRACTS.md` (what's landed).
5. `test/score_document_test.dart` (the test style to mirror).

Not legal/architectural gospel — verify every partitura signature against `@main`
before you lean on it, since that repo moves fast.
