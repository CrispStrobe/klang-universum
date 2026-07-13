# Handover — author zero-knowledge tutorials ("primers") for every minigame

**Your mission:** so that a child with **zero** prior music knowledge can open
any minigame and play it through, write a short **primer** for each game (or a
shared one per module) that teaches exactly the facts it drills — each fact
**shown** (engraved notation) *and* **heard** (playable audio). The tutorial
framework is built and live; this is a **content-authoring** job (plus a little
wiring). Work in a feature branch + a worktree that is a **sibling of `mus/`**
(so the `../partitura` path dep resolves). Keep `origin/main` green.

## What already exists (your starting point — don't rebuild it)

Framework in `lib/shared/tutorial/`:
- **`tutorial.dart`** — the model. `Tutorial(title, steps)`; each
  `TutorialStep(text, {score, play, playLabel})` = text + an optional partitura
  `Score` (drawn on a StaffView) + an optional `void Function(AudioService)`
  audio example.
- **`tutorial_sheet.dart`** — renders a `Tutorial` as a paged modal.
  `showTutorial(context, t)` opens it; `maybeShowTutorial(context, gameId, build)`
  opens it once per game (SharedPreferences-gated). `resetTutorialSeen(id)` for
  tests.
- **`tutorial_button.dart`** — a "?" `TutorialButton(builder:)` (for a future
  shared `GameAppBar`; not wired to screens yet).
- **`primers.dart`** — the authored content + shared helpers. **This is where
  you add primers.**

Wiring:
- **`GameInfo.tutorial`** (`features/games/game_registry.dart`) — an optional
  `Tutorial Function(AppLocalizations)?` hook per game.
- **`features/games/tutorial_gate.dart`** — `gameRoute(game)` wraps a game so its
  primer auto-shows on the first visit. **Only `module_screen` uses `gameRoute`**
  (recital/curriculum use the plain route on purpose — a showcase of known games
  shouldn't pop tutorials).

Already authored (5 modules, attached to their entry games):
`readingPrimer`→`note_reading_treble`, `noteValuesPrimer`→`note_value_quiz`,
`measuresPrimer`→`measure_fill`, `scalesPrimer`→`scale_detective`,
`chordsPrimer`→`triad_builder`. Copy their shape.

## Recipe — adding one primer

1. **Write the factory** in `primers.dart`:
   ```dart
   Tutorial harmonyPrimer(AppLocalizations l10n) => Tutorial(
         title: l10n.primerHarmonyTitle,
         steps: [
           TutorialStep(text: l10n.primerHarmonyStep1, score: _notes([...]),
               play: (a) => a.playChordSequence([[...],[...]])),
           // 2–4 steps, each showing and/or hearing one idea.
         ],
       );
   ```
2. **Add ARB strings** to **both** `lib/l10n/app_en.arb` and `app_de.arb`
   (`primerHarmonyTitle`, `primerHarmonyStep1`, …), then `flutter gen-l10n`.
3. **Attach** it: add `tutorial: harmonyPrimer,` to the game's `GameInfo` in
   `game_registry.dart` (put it on the module's **entry/simplest game**; add it
   to other games in the module only where they teach something distinct).
4. **Test**: add the primer to the loop in `test/tutorial_test.dart`
   ("every module primer builds and renders") so a broken ARB key / bad Score is
   caught. Run `flutter test test/tutorial_test.dart`.

### Helpers you already have (in `primers.dart`)
- `_notes(List<int> midis, {DurationBase dur = quarter})` → a one-measure treble
  staff of those MIDI notes.
- `_chord(List<int> midis)` → a single stacked whole-note chord.
- `_run(List<int> midis, {int ms = 320})` → `List<(int,int)>` for `playSequence`.
- `const _cMajor`, `const _aMinor`.

### AudioService methods (via the `play:` callback)
`playMidiNote(midi)`, `playMidiChord(midis)`, `playArpeggioThenChord(midis)`,
`playSequence(List<(midi,ms)>)`, `playChordSequence(List<List<int>>)`,
`playCadenceThenTarget(cadence, target)`, `playNoteLength(beats, isRest:)`,
`playPhrase(midis, gain:)`, `playCountedNote(beats)`.

### Notation (in a `score:`)
`Score(clef: Clef.treble|bass, measures: [Measure([NoteElement.note(pitch, dur,
id:'x')])])`. `pitchFromMidi(int)` lives in `shared/midi_pitch.dart`. For a
stacked chord use `NoteElement(pitches: [...], duration: ..., id:)` (see
`_chord`). Bass-clef games → build the example with `Clef.bass`.

## Content guidelines

- **Zero prior knowledge.** No jargon without defining it in the same breath.
  2–4 short steps. Kid-friendly, warm, second person ("Listen — it climbs!").
- **Show AND hear.** Prefer at least one step with a `score` and one with a
  `play`. The whole point is seen + heard, not a wall of text.
- **EN + DE, both.** German note naming: **B = H** (write "A H C D E F G",
  "C-Dur", "a-Moll"). Keep DE natural, not a literal gloss.
- **Teach the fact the game tests.** A bass-clef game's primer shows bass-clef
  notes; an interval game plays two notes and names the gap; a rhythm game
  claps/plays beats. Match the primer to what the child must recognise.
- **Legal:** distil facts in our own words. **Never** copy text/tables/exercises
  from any curriculum or method book (see the CLAUDE.md "Curriculum" note).

## The work-list (100 games, 13 modules)

Strategy: **one primer per module** on its entry game covers most of the module;
add a **per-game** primer only where a game teaches a distinct fact (marked ★).
Done ✅ already.

- **note_values** ✅ (note_value_quiz). ★ maybe: `rhythm_tap`/`beat_count` (beats
  & counting) if distinct from durations.
- **note_reading** ✅ treble (note_reading_treble). ★ `note_reading_bass`
  (bass clef — different lines), `ledger_leap` (ledger lines), `step_skip`,
  `pitch_sort`, `accidental_sort` (sharps/flats), the `*_bass` variants.
- **measures** ✅ (measure_fill). ★ `time_signature`, `strong_beat` (downbeat).
- **scales** ✅ (scale_detective). ★ `key_sig` (key signatures), `interval`-ish.
- **chords** ✅ (triad_builder). ★ `interval_ear`/`interval_ladder`/`connect_intervals`
  (intervals as a concept), `name_that_chord`, `chord_chart` (lead-sheet symbols).
- **harmony** — TODO. `harmony_quiz`, `roman_numeral`, `cadence_workshop`,
  `function_ear` (Tonic/Subdominant/Dominant; cadences; Roman numerals).
- **composition** — TODO. `ending_detective`, `question_answer`, `my_melody`,
  `free_sing` (phrases, question/answer, "finished vs open").
- **cello** — TODO. `cello_string_quiz`, `cello_finger_quiz`, `bowing`,
  `note_reading_tenor` (strings C-G-D-A, first position, tenor clef).
- **guitar** — TODO. `guitar_string_quiz`, `guitar_tab_read` (strings E-A-D-G-B-E,
  reading tab).
- **songs** — TODO. `sing_along`, `tune_quiz`, `song_book` (following a tune;
  singing back). Lightweight — mostly "how this screen works".
- **keyboard** — TODO. `key_find`, `key_name`, `key_ear`, `grand_staff_read`,
  `chord_grip_hero` (the piano layout, white/black keys, grand staff).
- **transpose** — TODO. `concert_pitch` (transposing instruments — keep simple).
- **drums** — TODO. `drum_read` (drum notation lines).

Get the current full list any time with:
`grep -nE "id: '" lib/features/games/game_registry.dart`.

## Gotchas & discipline (these bit us — heed them)

- **Auto-show breaks widget tests.** A modal popping on game entry hangs any test
  that drives that game. That's why `autoShowTutorials` (in `tutorial_gate.dart`)
  defaults **OFF** and is set true **only in `main()`** — tests never run
  `main()`. Don't "fix" this by editing tests; don't turn it on elsewhere.
- **No perpetual animations** in tutorial widgets — a looping `AnimationController`
  hangs `pumpAndSettle`. (The mascot learned this the hard way.)
- **`flutter test` hangs under the GEM-env wrapper.** Run `flutter test` plainly;
  the `env -u GEM_HOME …` wrapper is only for `pod`/`xcodebuild`/`flutter build`.
- **Pre-commit:** `dart format .` first (covers the ARBs + generated l10n), then
  `flutter analyze` (strict; must be "No issues found"). CI's format step checks
  the whole tree.
- **Hot shared files:** `game_registry.dart` and the ARBs are edited by parallel
  agents constantly. Keep edits small and additive, `git pull --rebase origin
  main` often, and update the `docs/PLAN.md` board at each checkpoint. Rebases
  will happen — keep commits small so they stay clean.
- **CI:** app CI runs `flutter analyze` + `flutter test` on push to main/PRs; the
  web deploy builds `flutter build web` — keep `dart:ffi` out of any web path
  (not a tutorial concern, but don't import the AEC plugin here).

## Also open (not primers, but adjacent — pick up if you like)
- A shared **`GameAppBar`** carrying the **"?"** `TutorialButton` (reopen a
  primer) **and** the existing `SoundToggle`, adopted per screen — this makes the
  sound toggle app-wide too. See PLAN.md "Learnability & UX".
- Mascot → speech-bubble presenter **before** the question (currently it's in
  `FeedbackLine`; give it an idle-alive presenter role in `RoundHeader`).

Details + rationale: `docs/PLAN.md` → "Learnability & UX"; auto-memory
`mus-ux-learnability`.
