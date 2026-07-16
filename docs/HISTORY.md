# KlangUniversum — Shipped history

The record of what's been built and lives in production
([mus-theta.vercel.app](https://mus-theta.vercel.app)). Forward-looking work —
what's pending and planned — lives in [PLAN.md](PLAN.md); this file is the
changelog it graduated from.

## Progression

- **Stars persist** (`ProgressService`): best stars/score and play count per
  game, shown on every game tile.
- **Star-driven difficulty**: 2+ stars widen a game's material (reading
  games gain the ledger range incl. middle C; Scale Detective gains D and A
  major; Measure Filler gains sixteenths). More expansions per game over
  time — SM-2 mastery stays the long-term signal, stars the session signal.
- **Soft unlock gating**: a module unlocks once the *previous* one has
  ≥ `kModuleUnlockTracked` SRI-tracked items (the child genuinely played
  there). Engagement gate, not a mastery gate — mastery gating proved too
  slow for a 6-year-old's first week. Locked cards explain what to play
  first.

## Audio (v1)

`core/audio/synth.dart` synthesizes everything in pure Dart — no assets, no
licensing: piano-ish additive tones (pitches, chords, arpeggios, sequences)
rendered to WAV and played via `audioplayers` (data-URI source on web), plus
CrispFXR-style retro square-wave SFX (correct blip, wrong buzz, fanfare —
same procedural approach as the maintainer's
[CrispFXR](https://github.com/CrispStrobe/CrispFXR-web) /
[crispaudio](https://github.com/CrispStrobe/crispaudio) projects, in Dart).
`AudioService` wires it app-wide; feedback sounds run centrally through
`QuizRoundMixin`. First ear game shipped: Major-or-Minor.

**Selectable instrument voices:** the synth carries four timbres — piano, a
reedy sustained **cello**, a soft **flute**, and a bright fast-decaying **music
box** — each a distinct harmonic profile + attack/decay. Settings has an
instrument picker (icon chips, previews on tap); the choice persists and drives
all pitched playback app-wide (retro SFX unchanged).

## Composition Workshop

A section *outside* the minigames (home-bar piano button) — a full touch- and
desktop-first score editor built on an editable `ScoreDocument` (a flat element
stream packed into bar-lined measures, with multi-level undo/redo). The grown-up
sibling of the My Melody sandbox. What it does now:

- **Entry** — pick a note value (whole…sixteenth, dotted) + accidental; write by
  tapping the staff, tapping the on-screen **sweepable piano** (C1…, octave
  labels), or the **computer keyboard** (A–G pitches, 1–5 values, R rest, arrows,
  `.` dot, `S` slur, Del, ⌘/Ctrl Z·Y·C·X·V). A blank-staff click *places* a new
  note (like a piano key); an existing note is re-pitched by dragging it up/down.
- **Chords** — a ⧉ toggle stacks pitches at one timeslot; the model is multi-pitch.
- **Selection & editing** — tap to select, **marquee** (⛶ rubber-band) to select
  a range; move/copy/cut/paste, transpose (↑/↓), set duration/accidental, delete.
  **Fine drag-reorder**: a horizontal note drag moves it to the exact drop slot
  (across bars and wrapped lines); a vertical drag re-pitches.
- **Notation** — dynamics · articulations · ties (anchored palette) · **slurs** ·
  **crescendo/diminuendo hairpins** · **multi-verse lyrics** (inline field +
  verse selector) · **pickup / anacrusis** (top-bar dropdown) · a visible
  insertion **caret** · single staff or **grand staff** (auto-split by pitch).
- **Chrome** — clef/time/key/zoom/pickup fold into one top row; an (i) sheet
  lists the keyboard shortcuts; leaving with unsaved work asks keep/discard/save;
  the engraving width is bound to the viewport so systems break on-screen.
- **I/O** — a single **Open…** picker reads any supported score by extension —
  MusicXML (+ compressed `.mxl`), MIDI, ABC, MEI, Humdrum `**kern`, MuseScore
  (`.mscx`/`.mscz`), Guitar Pro (`.gp`/`.gpx`) — and a single **Export…** sheet
  writes MusicXML/`.mxl` · MIDI · ABC · MEI · `**kern` · MuseScore · LilyPond ·
  Braille · **SVG** (font embedded) · **PNG**, saving via the system dialog (text
  formats fall back to a copyable view where a platform has no save picker). All
  parsers/writers are pure-Dart (web-safe). Also save to the Song Book. The macOS
  file pickers work now (added the `files.user-selected.read-write` sandbox
  entitlement — the app is sandboxed, so without it the dialogs were blocked).

Editing extras that lean on crisp_notation's editor contracts: caret (C2), drag-move
(C3), grand staff (C5), element hit-regions for marquee + fine reorder
(**C7** `ElementRegionController`), and one-call `Score→PNG/SVG` export
(**C8**). Detail + roadmap: `docs/WORKSHOP_PLAN.md`.

## Live microphone & pitch detection

The app's first **real-instrument input** (the structural gap every strong rival
had and we didn't). Pure-Dart chain: mic → PCM → pitch/chroma analysis, no
plugins beyond capture.

- **Play-along / Sing-along** — a **moving score**: target notes scroll
  right-to-left past a fixed "now" line while your live pitch is drawn as a dot,
  so you see yourself land on (or drift from) each note. Scoring is a pure
  `PlayAlongEngine` (right pitch — optionally octave-agnostic for voices —
  within a cents window for enough of the note); the screen just drives the
  Ticker clock, feeds it mic readings, and paints. No audible backing on purpose
  (the mic would hear the speaker; a Preview button plays it first).
- **Tuner** (cello corner) — open the mic, detect the note, show cents sharp/
  flat on an intonation meter. The whole chain mic → PCM → detector → meter.
- **Chord Listener** — fuzzy chord recognition from the live mic: strum/play a
  chord and it names the closest match with runner-up guesses and the 12-bin
  pitch-class profile it heard (chroma analysis — "name the chord" beats
  "transcribe every note").
- **Perform It** (note reading) — mic-graded *reading*: a note is shown and the
  child **plays or sings it** — the pitch detector verifies it (octave-agnostic,
  held briefly to avoid false hits) instead of a letter tap. Live detected-note
  readout, star-gated range, skip button, mic-permission handling; feeds the
  shared `note_reading.<clef>.*` SM-2 pool. The kid-scale core of performance-
  graded sight-reading.
- **Sing Back** (scales/ear) — ear→voice: a note *plays* (not shown), the child
  **sings it back**, and the mic checks the pitch (octave-agnostic, held
  briefly). A "hear it again" button, the answer reveals on a correct sing, skip
  + mic-permission handling. Trains pitch memory and matching with no instrument;
  feeds the ear pool `scales.hear.sing_<step>`.
- **Sing the Interval** (Chords) — ear→voice on the *interval*: two notes play,
  low then high, its name is shown ("a fifth"), and the child **sings the top
  note back** (mic checks the pitch class, octave-agnostic). The sung twin of
  Interval Ear — builds interval vocabulary *and* the voice to reproduce it.
  Reuses the Sing Back capture harness + crisp_notation's `Interval` /
  `Pitch.transposeBy`; third/fourth/fifth for beginners, second + sixth at 2★.
  SRI `intervals.sing.<name>`.
- **Cello Play It** (Cello Corner) — mic grading on the *real instrument*: a
  first-position note is shown on the bass staff with a string + finger hint;
  the child bows it on their cello and the mic verifies the pitch
  (octave-agnostic — kind to the low C string — held a touch longer to shrug off
  the bow's scratchy attack). "Hear it" + skip buttons, mic-permission handling.
  Turns the finger/string knowledge active; feeds the cello play pool
  `cello.play.<step><octave>`.

## Curriculum (Lehrplan alignment)

A **Curriculum** screen (home-bar 🏫) that maps the games onto a syllabus.
Deliberately **un-branded, generic progress levels tied to school years**
(Klasse 1–2 … 9–10) — the topic scope distilled in our own words from public
school curricula, no badge/association branding. A small data engine
(`Curriculum → Level → Topic → gameIds`) with topic labels reused across levels;
per-region variants are drop-in data (`region` field).

- **Readiness** per level/topic = **star coverage × SM-2 retention**: breadth
  (played + performed the games) modulated by whether skills actually stuck
  (`SriService.masteryUnder(namespace)` — mean per-item mastery, neutral until a
  namespace is practised so there's no discouraging cold start).
- Study guidance: a **"continue here"** marker on the recommended level, and
  **"practise your weakest topic"** — both running curated recitals of the
  relevant games. A test guards every mapped game ID against the registry.
- Internal licensing rationale (why no D-branding) lives in the gitignored
  `CLAUDE.md`, not here.

## Playtest cycle — polish, reworks & tools

A full parent/child playtest pass. Grouped by kind.

**Correctness & UX fixes:** Symbol Quiz renders note/rest **on a staff** (rests
now identifiable) · Rhythm Echo **sounds from the first tap**, rings while held ·
Sort the Beats — much **larger bucket glyphs** + the bottom **mascot reacts** ·
Connect columns pulled **close together** · Line or Space is **tappable** (+
arrow keys), not swipe-only · Falling Notes **starts ~half speed** · Triad
Builder is a **single measure** (taps land where the note appears) · My Melody
uses an **adaptive clef** (a cello's low C shows in bass) · Song Book karaoke
highlight **no longer drifts** behind the audio · Cello "Which String?" is scoped
to the **open strings** (unambiguous).

**Pedagogy reworks** (games that "made no sense"): **Follow the Conductor** →
real **conducting patterns** (metre/downbeat) · **Beat Runner** → a **rhythm-
reading lane** (note-value markers spaced by their true durations) · **Scale
Detective / Builder** → harder, into **minor keys** (harmonic minor defeats the
spot-the-accidental shortcut) · **Sound Echo** → noteheads on the pads with
**cues that fade** (colour → sound → read alone).

**Deeper features:** Melody Echo **lights notes L→R** as a card plays · Melody
Dictation **edit-in-place** (tap a note to re-pitch/delete) · **bass-clef
variants** of Line or Space, Note Order, Falling Notes and Connect (violin +
bass, own SRI + stars) · **keyboard control** app-wide (number keys select any
answer grid; arrow keys drive Line or Space & the Conductor; space/enter the
rhythm lane; C–B letter keys catch Falling Notes) · **Progress "tricky spots"**
now shows every skill (coloured module icons, skill-typed labels), not just
notes · **Tenor Clef reading** is gated as an advanced unlock — the tile shows
locked until the child has 2★ in both other Cello-Corner games (a general
per-game `unlockedWhen` gate on `GameInfo`).

## Opportunity backlog — shipped

- **Note-naming toggle:** German H/B, English, solfège — one setting, every
  drill. Reinforces EN/DE.
- **Daily streak + practice calendar** (flame + count + 7-day dots on home;
  finishing a game marks the day).
- **"Wait mode" pacing** — advance only on the correct answer, no timed fail
  (`QuizRoundMixin` retries until correct, no timers/lives anywhere); guarded
  by a contract test.
- **Reacting mascot** — a pure-Dart quarter-note character in the shared
  feedback line: hops + grins on correct, damped wobble + "oops" on wrong;
  reduced-motion aware.
- **Opt-in timer + beat-your-time** — off by default; when on, the result
  screen shows completion time + personal best + "new best!" (no live clock).
- **Bilingual EN/DE pedagogy** foregrounded — the note-naming toggle advances
  it in-app; the rest is positioning.
- **Weak-spot ear engine + "your tricky notes"** — `SriService.weakestItems`
  + a card on the Progress screen with readable labels; SM-2 re-drills them.
- **Functional cadence → scale-degree ear mode** — "Hear the Function"
  (harmony): a I–IV–V–I cadence establishes the key by ear, then a target
  chord is named T/S/D. SRI `harmony.hear.*`, review-routed.
- **Landmark / intervallic reading hints (fading)** — the Reading Quiz shows a
  landmark chip ("a skip up from E") anchoring on memorized lines + middle C;
  fades with mastery (gone at 3★ and in review). `reading_hint.dart`.
- **Written melodic dictation** — **Melody Dictation**: a melody plays (audio
  only), the child writes it by tapping noteheads onto the InteractiveStaff,
  per-note feedback + undo + note-for-note check. SRI
  `note_reading.dictation.len3`. (Rhythm dictation served by Rhythm Echo.)
- **Removable colour scaffold** — Settings toggle "Colour helper for beginners"
  (off by default) tints noteheads + choices by pitch class (Boomwhacker,
  `note_colors.dart`) in Reading Quiz + Place the Note, with a legend.
- **Play-in-time lane** — **Beat Runner**: note-value markers fall spaced by
  their REAL durations over a steady click; tap each as it crosses the
  hit-line. Ticker master clock, space/tap, Perfect/Good by accuracy.

## Gamified formats — shipped

- **Longest First** (Notenwerte) — the ordering/sequence format on note *values*:
  four shuffled note-value symbols; tap them longest → shortest, each playing its
  own duration and locking with a number badge, a wrong tap buzzes. The
  note-values sibling of Note Order (which orders pitches). SRI
  `note_values.order.len<N>`.
- **Note Match** (memory / concentration pairs) — flip a grid to pair a
  note-on-staff with its letter; each flip plays the pitch; fewer moves → more
  stars. SRI on each match.
- **Note Order** (sequence / ordering) — tap four shuffled note cards from
  lowest pitch to highest; each correct tap plays + locks with a badge. SRI
  `note_reading.order.len4`.
- **Sort the Beats** (sort into buckets) — drag note-value symbols into their
  1 / 2 / 4-beat bucket; wrong drop bounces + buzzes. SRI `note_values.symbol.*`.
- **Line or Space?** (swipe binary drill) — swipe a note-card left = line,
  right = space; wrong swipe bounces back. SRI `note_reading.line_space.*`.
- **Falling Notes** (arcade) — notes rain down real crisp_notation staves; name the
  glowing one on a 7-letter pad before it crosses the neon hit-line. Combo
  ×1–×5, speed ramps every four catches, three hearts, fixed 15-note run,
  star-driven range, colour-scaffold, reduced-motion aware. Feeds
  `note_reading.treble.*`. The **"play it" variant** ships too: **Falling Keys**
  drops the same notes onto a piano keyboard (SRI `keyboard.find.*`).
- **Connect the Notes** (connect-a-line matching) — notes on staves left, names
  shuffled right; drag a wire from each note to its name (`CustomPaint`).
  Correct link locks + plays; clears to advance. SRI `note_reading.treble.*`.
  The **symbol↔meaning** column ships as **Connect the Symbols** (Notenwerte,
  `note_values.symbol.*`) — same engine, a `mode` flag. A third mode,
  **Connect the Steps**, links an interval on a staff (two half-notes) to its
  *number* — count the note-names, C→G spans 5; 6th/7th join at 2★. SRI
  `intervals.size.*`.
- **In the Scale?** (swipe/tap binary) — a note on a card; swipe/tap/arrow-key
  IN if it belongs to C major (a natural), OUT if it's sharpened (chromatic).
  Wrong bounces back. SRI `scales.member.<in|out>`.
- **High or Low?** (sort into two baskets) — treble notes above vs below the
  middle line drag into HIGH / LOW baskets; correct drop sounds the note. The
  Sort-the-Beats bucket format on pitch *direction*. SRI `pitch.height.*`.
- **Sharp or Flat?** (sort into two baskets) — each note carries a sharp or a
  flat; drag it into the matching basket. Reading the accidental sign is the
  skill. SRI `accidentals.sign.*`.
- **Dotted or Not?** (sort into two baskets) — drag note glyphs into Dotted /
  Plain baskets by reading the **augmentation dot** (which makes a note half
  again as long). The note value varies (half/quarter/eighth) so the shape alone
  doesn't give it away. Reuses the Sharp-or-Flat? sort scaffold. SRI
  `note_values.dot.<dotted|plain>`.
- **Higher or Lower?** (ear, binary) — two notes play in sequence; tap whether
  the second is higher or lower. No staff — the aural twin of High or Low?. Big
  replay button. SRI `pitch.hear.<up|down>`.
- **Same or Different?** (ear, binary) — the youngest pitch-discrimination skill
  (Kodály): two notes play; tap whether they are the same pitch or different. A
  clear leap for beginners, subtler gaps (down to a semitone) at 2★. Replay
  button, no staff. SRI `pitch.hear.<same|diff>`.
- **Ascending or Descending?** (ear, binary) — a short run of notes plays; tap
  whether it climbs up or steps down. A step past Higher or Lower? — a whole
  phrase moves one way, not just two notes. Three notes for beginners, four at
  2★. Replay button, no staff. SRI `pitch.hear.<asc|desc>`.
- **Step or Skip?** (staff reading, binary) — two notes on the staff; read
  whether the move is a step (the next line/space, a 2nd) or a skip (a bigger
  leap). The motion vocabulary that precedes naming exact intervals. Correct
  answer sounds both notes. SRI `reading.motion.<step|skip>`.

## CrispNotation-powered — shipped

Games built on crisp_notation capabilities the app didn't use before.

- **Tie or Slur?** (Noten lesen) — reads the two curved marks that look alike but
  mean different things: a **tie** joins the *same* pitch (`NoteElement.tieToNext`),
  a **slur** joins *different* pitches (`Score.slurs`). A binary staff-read like
  Step or Skip?; the card engraves the two-note figure, two buttons, audio on
  correct. SRI `reading.curve.<tie|slur>`.
- **Beam or Flag?** (Noten lesen) — the two looks of eighth notes: joined by a
  **beam** (two eighths on one beat) vs each keeping its **flag** (eighths split
  by an eighth rest). The engraver has no beam-suppression API, so the cards
  exploit the real rule; the beam/flag contrast was verified at the crisp_notation
  layout level (same-beat eighths → 1 `BeamPrimitive`, eighth-rest between → 0).
  SRI `reading.beam.<beamed|flagged>`.
- **Connect the Notes — four new modes** (Notenwerte) — the connect-a-line board
  grew from 3 to 7 modes, each one `ConnectMode` case reusing an existing catalog
  so nothing drifts: **Dynamics** (mark glyph ↔ meaning, `connect_dynamics`,
  shares `reading.dynamics.*` with Louder or Softer?), **Rests** (rest glyph ↔ the
  note it equals in length, `connect_rests`, `note_values.rest.*`), **Tempo Words**
  (Italian term ↔ meaning, `connect_tempo`, shares `reading.tempo.*` with Faster
  or Slower?), **Beats** (note value ↔ how many beats in 4/4, `connect_beats`,
  `note_values.beats.*`).
- **Sharp / Natural / Flat — 3-basket sort** (Noten lesen) — *Sharp or Flat?*
  (`accidental_sort`, +bass) widens at 2★ to a three-basket sort adding the
  **natural** sign, rendered as a real ♮ via `NoteElement.showAccidental` on an
  unaltered pitch; below 2★ it stays the binary ♯/♭ drill. Card sign refactored
  bool→`int alter`. SRI gains `accidentals.sign.natural`.
- **Triad or Seventh?** (Chords) — an ear game on the added seventh: a major
  triad (3 notes) vs a dominant-7 (triad + a minor 7th, 4 notes), tap which. The
  dom7 is built app-side from the major `Triad`'s pitches +
  `root.transposeBy(Interval.minorSeventh)` — no 7th-chord *builder* needed from
  crisp_notation. Completes the chord-quality-by-ear widening. SRI
  `chords.hear.<triad|seventh>`.
- **Read the Voice** (Noten lesen, gated behind Duet 2★) — reading one line out
  of a multi-voice texture, on crisp_notation's `Measure.voice2` (two voices per
  staff, stems up/down). A chord is shown with one voice highlighted; the child
  names the note *that* voice sings, so they must track the right line. The
  4-voice generalization of Duet: difficulty grows 2 voices (Soprano + Alto, one
  treble staff) → full **SATB** (four voices across a grand staff via
  `StaffSystem`). Voiced with a no-crossing `nextChordTone`-above algorithm (bass
  in octave 3, alto pushed to middle C so S/A land on treble, T/B on bass).
  C major; a "hear this voice" button; SRI feeds the shared reading pool. First
  of three scoped SATB minigames.
- **Which Voice?** (Noten lesen, gated behind Duet 2★) — the inverse of Read the
  Voice: a note in the chord is highlighted and the child picks which voice it is
  (Soprano/Alto/Tenor/Bass). Trains voice-position and range awareness (where
  each voice lives on the grand staff) rather than pitch naming. Same 2-voice →
  SATB progression, shared `satb_voicing.dart`. SRI `note_reading.voice.<voice>`.
  Second of three scoped SATB minigames.
- **Hear the Voice** (Noten lesen, gated behind Duet 2★) — the aural SATB game:
  the full chord plays, then one voice alone, and the child identifies which
  voice they heard (S/A/T/B). No notation — pure ear-training; at 2 voices it's
  "higher or lower?", at full SATB the inner voices make it a real listening
  challenge. Shared voicing, cancellable audio timers, a replay button. SRI
  `note_reading.ear_voice.<voice>`. Completes the three scoped SATB minigames
  (Read / Which / Hear the Voice).
- **"Handwritten notes" theme** (Settings) — a toggle that renders all notation
  in **Petaluma**, Steinberg's jazz/handwritten SMuFL face (SIL OFL 1.1),
  instead of Bravura. The font (+ metadata + OFL) is vendored in
  `assets/smufl/`; its licence shows on the About page. Every StaffView /
  MultiSystemView site now routes through `shared/score_theme.dart`'s
  `kidsScoreTheme`, which applies the selected `MusicFont` (Bravura by default);
  the toggle updates a global so screens entered afterwards pick it up. A
  cosmetic delight, and the plumbing for further faces (Leland/Leipzig) later.
- **Chord Chart** (Chords) — lead-sheet literacy: a chord *symbol* is shown
  (G, Dm, D7…) and the child taps the matching *notation* among four little
  staves. The inverse of Name That Chord (notation→symbol); symbols come from
  `chordSymbolFor` so they're spelled as the library names them. Correct tap
  plays the chord; widens major/minor triads (roots C/F/G) → all roots → +
  diminished. SRI `chords.symbol.<symbol>`. Uses the shared game-test harness.
- **Strong Beat?** (Takte) — metric-accent training on crisp_notation-public's
  `beatStrength`. A measure is shown with its beat numbers (crisp_notation's
  `showBeatNumbers`), one beat highlighted; the child says whether it's a strong
  (accented) or weak beat. The answer is graded by
  `TimeSignature.beatStrength(position)`, not hard-coded — correct for 4/4 (1 & 3
  strong), 3/4 (only 1) and 6/8 (1 & 4). A metric click accents the strong beats.
  Widens 4/4 → +3/4, 2/4 → +6/8. SRI `measures.accent.<ts>_<beat>`.
- **Roman Numerals** (Harmonik) — read *and* hear a diatonic triad in a key and
  pick its Roman numeral (I, ii, iii, IV, V, vi, vii°). The chord is built with
  `Triad(root, quality)` and named by crisp_notation-public's new
  `romanNumeralOf(pitches, key)` — the same analyser will later carry sevenths
  (`V6/5`), inversions and minor keys. A step up from the Function Quiz (T/S/D
  only): every diatonic degree is in play. Renders the chord with the key
  signature, arpeggio-then-chord audio + replay, four numeral buttons. Widens
  I/IV/V in C major → all seven degrees → all easy major keys. SRI
  `harmony.roman.<symbol>`. *(First game on the crisp_notation-public alignment — mus
  now builds against `CrispStrobe/crisp_notation@main` locally and on CI.)*
- **Name That Chord** (chords) — read or hear a chord and pick its symbol; the
  answer is graded by crisp_notation's `identifyChord`, so it names quality **and**
  inversion. Roots C–A (no accidental in the symbol); major/minor root position
  for beginners, diminished/augmented and slash-chord inversions (C/E) at 2★.
  Renders the chord as a block on the staff, replay button, keyboard 1–4. SRI
  `chords.name.<root>_<type>`.
- **Chord Builder** (chords) — build the named chord by tapping three notes onto
  the staff; crisp_notation's `identifyChord` grades what you built, so **any voicing
  counts** — root position or an inversion, in any octave. The interactive
  counterpart to Name That Chord; major/minor for beginners, dim/aug at 2★. SRI
  `chords.build.<root>_<quality>`.
- **ABC import** (Song Book) — the importer takes pasted **ABC notation**
  (`scoreFromAbc`) alongside MusicXML / ChordPro / MIDI, stored as MusicXML like
  the rest. Opens the large public-domain ABC folk-tune libraries; the tune's
  `T:` line seeds the title.
- **Concert Pitch** (new **Transposing** module/corner) — read a written note
  for a **B♭ trumpet / E♭ alto sax / F horn** and name the concert pitch that
  actually sounds; crisp_notation's `transposeBy` computes the exact letter. The B♭
  instruments alone for beginners, E♭ and F added at 2★. A skill nothing else in
  the app covers. SRI `transpose.<instrument>.<written-step>`.
- **Bowing** (cello corner) — read crisp_notation's string-bowing marks: a note on
  the bass staff carries a ⊓ down-bow or ∨ up-bow (`Articulation.downBow/upBow`);
  name it. SRI `cello.bowing.<down|up>`.
- **Which Beat?** (measures) — a 4/4 bar with one note coloured; tap the beat it
  starts on (1–4). crisp_notation's **`showBeatNumbers`** overlay draws the count
  under the staff as a scaffold that fades (on at level 1, off at 2★). SRI
  `measures.beat.<n>`.
- **Time Signatures** (measures) — read a signature — including the **C
  (common)** and **¢ (cut)** glyphs — and give the beats per bar. 3/4·4/4·C for
  beginners; ¢·6/8·2/4 at 2★. SRI `measures.timesig.<id>`.
- **ABC export** (Composition Workshop) — an AppBar action renders the current
  score to **ABC** (`scoreToAbc`) in a dialog and copies it to the clipboard;
  round-trips with the Song Book's ABC import.
- **Duet** (note reading) — read the **highlighted part of a two-staff system**
  (crisp_notation's `StaffSystemView`): two parts are shown, one note highlighted;
  name it, tracking the right line. Both treble for beginners; the lower part
  becomes bass clef at 2★, like a grand-staff duet. SRI
  `note_reading.<clef>.*`.
- **Drum Read** (new **Drums** corner) — read a two-bar rhythm on the neutral
  **percussion clef** and tap it back on the drum pad. After a one-bar count-in
  the notation goes live; each tap is judged Perfect/Good/Miss against the
  notated onsets over a steady click (one Ticker master clock, no drift). A
  no-fail performance toy.
- **Which Clef?** (Noten lesen) — the youngest clef-literacy drill: a bare clef
  is drawn on an empty staff (`StaffView` over `Measure([])`) and the child taps
  which clef it is. Treble vs Bass for beginners, widening to **Alto and Tenor**
  at 2★ (all four rendered by crisp_notation's `Clef`). A binary `AnswerGrid`, no-fail;
  nothing else in the app taught reading the clef *sign* itself. SRI
  `reading.clef.<treble|bass|alto|tenor>`.
- **Whole or Half Step?** (Noten lesen) — the tone-vs-semitone drill and the
  foundation of scale-building: two neighbour notes (a 2nd) are shown; tap
  whether the gap is a whole step or a half step, then hear it played. Because
  half steps hide only at E–F and B–C, a plain 2nd isn't enough — the child must
  read the letters. Balanced generation (`Clef.pitchAt`), naturals only; treble
  for beginners, +bass clef at 2★. The natural sequel to Step or Skip?. SRI
  `reading.tone.<whole|half>`.

## Toy-inspired mechanics — shipped

- **Strum Toy** (guitar corner) — a free, no-scoring jam: pick an open chord
  (C/G/D/Em/Am) and swipe across the strings to strum (down = low→high, up =
  high→low) or tap one to pluck. Voiced as an arpeggio-into-block-chord (the
  synth is monophonic), colour-coded strings, keyboard 1–5 + space/arrows.
- **Sound Echo** (memory-sequence toy) — four pentatonic pads; the app lights +
  plays a growing sequence, the child echoes it; one miss ends the run. Made
  educative: noteheads on a mini-staff (C-major pentatonic) and **cues fade as
  the sequence grows** — colour + sound + notation first, then colour drops,
  then sound, until the longest runs are read from noteheads alone.
- **Follow the Conductor** (command caller, reworked into a metre lesson) — the
  baton traces the real conducting figure for the time signature (2/4, 3/4,
  4/4); the target zone lights on each beat (accented downbeat) and the child
  follows — taps or arrow keys. Scored by timing; kinaesthetic downbeat.

## Original concepts — shipped

- **Tracker** (composition) — a touch-first **pattern sequencer** in the spirit
  of ModEdit / FastTracker 2 / Scream Tracker 3 / Impulse Tracker, but
  **dual-audience** (a 10-year-old builds a groove; an adult finds it cool) via
  two skins over one document — the same Sandbox/Studio idea as the Workshop.
  Pick an instrument tab, tap a **scale-locked pentatonic piano-roll** (pitch
  rows × step columns), and every channel layers into one looping groove. It's
  the Loop Mixer with an **editable grid**: `tracker_engine.dart` renders each
  channel to a stem and sums them through `synth.dart mixStems` → one looping
  WAV on `LoopPlayerService`, with the same Stopwatch-phase swap (edits re-enter
  the loop in phase) and Ticker playhead. Instruments hang off a
  `TrackerInstrument` seam: **additive** timbres, **sfxr chiptune** (a focused
  pure-Dart port of the maintainer's
  [crispaudio](https://github.com/CrispStrobe/crispaudio) SynthEngine into
  `core/audio/crisp_dsp/sfxr.dart` — blips/zaps/booms synthesized per-note at
  pitch), and **recorded voice**: the flagship *record-your-voice → play a tune
  with it* bridge — `voice_clip_recorder.dart` captures a mic clip, a voice
  effect (chipmunk/monster/deep via a ported **formant shifter**, robot via
  ring-mod + bit-crush — all pitch-stable so the sample stays in tune) is
  applied, and it becomes a resampled tracker instrument on a runtime-swappable
  `voice` channel. All DSP ported (MIT) from the maintainer's crispaudio /
  CrispFXR / voicelab. Sandbox, no stars. (Mic capture is device-only; the
  DSP + assign→play path are unit-tested headlessly.)
- **Loop Mixer** (composition) — a kid **loop-layering toy**: five cards
  (drums · bass · chords · melody · sparkle) each toggle a pre-authored 2-bar
  loop; everything is C-pentatonic so any combination grooves (the Colour
  Melody rule). A sandbox — no stars, no wrong answers. Under the hood the
  first **multi-track** audio in the app, still pure Dart + one player:
  `loop_engine.dart` mixes the enabled tracks offline into a single looping
  WAV (sample-accurate sync for free), with **combo-independent levels**
  (unit-peak per stem + authored gains + a tanh soft-knee in
  `synth.dart mixStems` — toggling a card never changes the others' loudness)
  and **seeded noise percussion** (kick sweep / snare / hat one-shots — the
  additive synth is tonal, so drums got their own generator). The screen owns
  a Stopwatch musical clock and swaps mixes with `play(position: phase)`, so
  layers drop in/out **without the bar restarting**; a dedicated
  `LoopPlayerService` (ReleaseMode.loop) keeps SFX and groove from stopping
  each other. Step-dot playhead (Ticker), 75/100/120 BPM presets, per-combo
  render cache. Acceptance-tested end-to-end by rendering stems and reading
  them back with `bin/listen.dart` (bassline detected exactly as authored;
  pad reads C 98% → Am 98%).
- **Colour Melody** (composition) — a composing grid for **pre-readers**: five
  coloured rows (a C-major pentatonic, so every combination is consonant) × eight
  beats. Tapping a cell places a note (and sounds it), and the grid renders live
  to a **real crisp_notation `Score`** shown underneath — so a non-reader is
  quietly writing notation. Play the tune back (rests preserved via
  `playChordSequence`, empty beats = silence) or clear. A sandbox like My Melody —
  no stars, no wrong answers; the bridge to notation for those who can't read yet.
- **Find the Key (bass)** (keyboard) — the staff→piano bridge in bass clef: the
  reusable `PianoKeyboard` shifts two octaves down (C2..B3) so the low staff
  naturals (G2..A3) and the 3★ black-key targets land on real keys. Own
  `progressId`; the SRI token carries the octave so bass items never collide with
  the treble Find the Key. Completed the bass-clef sweep of the reading/keyboard
  games.
- **Recital Mode** (progression meta) — a home-bar "recital" strings a 3–5 piece
  programme (favouring games the child has already practised) into one set; play
  each in turn and the run ends on a **curtain call** that tallies the stars
  earned across the whole programme. Wraps the review loop in a set-piece.
- **Note Snake** (note reading) — reading meets the classic arcade snake: a
  target note shows on the staff, letters sit on a grid, and you steer the snake
  (arrow keys or an on-screen pad) to eat the letter that names it. Eating the
  wrong letter — or biting your tail — ends the run; it wraps at the edges and
  speeds up as you grow. Star-gated range, colour-scaffold, treble + bass. Feeds
  `note_reading.<clef>.*`.
- **Chord Grip Hero** (keyboard) — Falling Keys for chords: a triad falls on the
  staff and its keys glow on the piano; press all of them before it lands. Full
  grips speed up the next; three ungripped landings end the run. White-key
  diatonic triads of C major (playable without black keys); C/F/G major for
  beginners, the Dm/Em/Am minors at 2★. Feeds `keyboard.chord.*`.
- **Staff Runner** (note reading) — an endless sight-reading sprint: one note at
  the read-line with a depleting timer bar; name it before the bar empties.
  Every correct read shortens the next timer (the "speed up"); three misses
  (wrong name or timeout) end the run, score = notes read. Star-gated range,
  colour-scaffold, letter-key control, treble + bass. A stepping-stone to the
  generative-sight-reading big swing. Feeds `note_reading.<clef>.*`.
- **Interval Ladder** (chords & intervals) — interval *construction*: a base
  note is shown with a chip saying how far and which way to climb (▲3 = a third
  up); tap the candidate note at that interval (a correct pick plays base→target
  melodically). Thirds/fifths up for beginners, all sizes and both directions at
  2★. SRI `chords.interval.build.<n><up|down>`.
- **Dynamics & Tempo Charades** (expression) — expressive vocabulary the app
  didn't touch: a phrase plays at one of four tempi (Adagio→Presto) or four
  dynamic levels (pp→ff); name what you heard. The two clear extremes for
  beginners, all four terms at 2★. Needed a `gain` on the synth so dynamics are
  actually softer/louder (the output is otherwise peak-normalized). SRI
  `expression.hear.<tempo|dynamics>.<term>`.
- **Odd One Out** (note reading) — whack-a-mole under gentle reaction pressure:
  noteheads pop up in a 3×2 grid of holes, a target letter is called ("Whack:
  A") and the child taps the matching notes before they duck. Correct whacks
  grow a ×1–×5 combo; a wrong whack costs a heart (3 lives); a fixed 12-whack
  run keeps the score/1–3★ loop, with the hole lifespan shrinking as it goes.
  Ticker-driven, star-gated octave range, colour-scaffold aware, letter-key
  control, reacting mascot; treble + bass. Feeds `note_reading.<clef>.*`.
  *(Extends to a "wrong-note" spot-the-error mode.)*
- **Odd One Out** (note reading) — three note cards; two share the same letter
  name at different octaves, one is a different letter. Tap the odd one out — a
  discrimination drill that trains rapid name-reading, not just notehead
  matching. Star-gated octave range (staff → ledger), colour-scaffold aware,
  number-key control, reacting mascot; treble + bass variants. Feeds the shared
  `note_reading.<clef>.*` pool on the odd note. *(Extends to chord-quality and
  scale-degree "odd one out" by ear.)*
- **Ledger Leap** (note reading) — a note sits exactly on the Nth ledger line
  (never a space, so the count is unambiguous); tap 1 / 2 / 3. Star-gated
  (treble/middle-C region first; +bass, above, 3 lines at 2★). A correct count
  plays the pitch. SRI `note_reading.ledger.<clef>.<below|above><n>`.
- **Key Detective** (scales) — crisp_notation renders a key signature
  (`KeySignature(fifths)`); name the major key. Natural-letter tonics
  (C G D A E B F) so buttons never need an accidental; German B = H via the
  naming toggle. Star-gated (C/F/G/D → +A/E/B); correct answer plays the tonic
  triad. SRI `key_sig.<tonic>`.
