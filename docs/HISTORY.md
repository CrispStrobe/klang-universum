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

Notation-depth + Studio-shell + playback arc (2026-07, the parity push):

- **Notation depth** — **tempo marks** (initial `Score.tempo` + mid-score
  `Measure.tempoChange`), **grace notes** (a per-note pitch list, acciaccatura/
  appoggiatura), **ornaments** (trill/mordent/turn), **tuplets**, **mid-score
  clef/key/time changes**, **mid-*bar* clef changes** (`inlineClefs`), **repeats +
  voltas + navigation** (D.C./D.S./coda/segno/fine), and `RhythmPolicy.split` (tie
  over-long notes across barlines). All built on one id-anchor/field pattern on the
  flat document, all lossless through the MusicXML save→reopen.
- **Two voices** — an optional **voice 2** per part (`Measure.voice2`) with a
  V1/V2 toolbar toggle; the flat doc keeps `_v1`/`_v2` and the active voice drives
  entry, so the mutation sites are untouched.
- **Studio shell** — a **Sandbox/Studio shelf** toggle reveals grown-up depth
  (an **Insert/Select** input-mode toggle and a selection-driven **inspector**
  panel) together, while the kid Sandbox surface stays simple.
- **Playback** — a real **transport** with a moving cursor that highlights the
  sounding notes; **multi-part** playback mixes every part into one WAV with a
  **per-part mute**; a **practice-speed** control (0.5×/0.75×/1×) slows playback
  without changing pitch. Reflects repeats/navigation/split via the timeline.
  Two opt-in practice tools (⋮, default off): a **count-in** — a bar of clicks
  rendered into the same WAV so it can't drift from the music, counted in the
  meter's own beat unit — and **loop selection**, which repeats the selected range
  until Stop, clipping every part so the accompaniment loops with the melody.

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
- **Sing along / Play along with any Song Book song** — the song viewer has both
  buttons; each derives a target melody from the song's notation (`chartFromScore`
  — top pitch per note, timed from the playback timeline) and drops it into the
  same moving-score highway. **Sing along** is octave-agnostic (match it in your
  own range); **Play along** targets the written octave, for an instrument. Stars
  scale to the song's length (`scaledStarScore`), so a long song isn't a free 3★.
  Turns the Song Book (and the groove→Song Book export) into practice material.
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
- **On the Beat or Off?** (Takte) — reading + hearing **syncopation**. A straight
  bar (four quarters on the beats) vs a syncopated one (eighth + 3 quarters +
  eighth, so the inner notes land off the beat); playback uses the real note
  lengths so the push is audible. Fills the curriculum's syncopation gap. SRI
  `measures.syncopation.<straight|syncopated>`.
- **Even or Triplet?** (Notenwerte) — reading how a beat is split: two even eighths
  vs a **triplet** (a real `TupletSpan(0,2,actual:3,normal:2)` → the engraver draws
  the bracket + 3), heard as 2-in-a-beat vs 3-in-a-beat. Fills the triplet/tuplet
  gap. SRI `note_values.tuplet.<even|triplet>`.
- **Label the Form** (Komponieren) — hearing and *seeing* a piece's shape, an AnaVis-in-miniature. Each section is a short motif; a reusable `FormTimeline` widget draws the sections as colour-coded blocks (same colour = same tune), and the child picks the form — ABA / AAB / ABC for beginners, AABA / ABAB / rondo (ABACA) at 2★ (where the block labels hide, so the repeat pattern must be read from the colours). Fills the musical-form + verse/chorus gaps. SRI `composition.form.<FORM>`.
- **Which Ornament?** (Noten lesen) — read the sign over a note: **trill** (tr),
  **mordent** (squiggle), or **turn** (sideways S), drawn via `NoteElement.ornament`
  and each played as a little flourish (trill = fast alternation, turn = the curl
  around). Fills the ornaments gap. SRI `note_reading.ornament.<trill|mordent|turn>`.
- **Spot the Upbeat** (Takte) — a binary staff-read on where a tune begins: a
  short two-bar melody starts either on the downbeat (a full first measure) or
  with a **pickup / anacrusis** (an incomplete first measure — a few notes before
  the first barline). The pickup is a real `Measure(..., pickup: true)`, so the
  first bar genuinely holds less than the meter (a proper anacrusis, borrowed from
  the last bar). At 2★ the note-counting shortcut is defeated — full bars may use
  mixed rhythms (half + two quarters: three noteheads but still a full 4/4), and
  the pickup runs 1–2 notes — so the answer needs real metric reading. Correct →
  the melody plays. SRI `measures.upbeat.<yes|no>`.
- **Enharmonic Twins** (Noten lesen) — a binary staff-read on enharmonic
  equivalence, a Sek-I staple nothing else drills: two whole notes (each with its
  accidental) across two bars — **same sound spelled two ways** (F♯ = G♭) or two
  **genuinely different** pitches? Graded by `midiNumber` equality, so it is exact
  and the child must read past the spelling. Five sharp/flat twins for beginners;
  the trickier white-key twins (E♯ = F, F♭ = E) join at 2★; "different" rounds are
  guaranteed non-enharmonic and non-trivial (adjacent steps, at least one
  accidental). Correct → both notes play. SRI `reading.enharmonic.<yes|no>`.
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
- **Major or Minor?** (chords) — a drag-and-drop sort on triad **quality** read
  off the staff: each card shows a triad; drag it into the Major or Minor basket
  (the third is what decides it). The reading twin of the aural Dur-oder-Moll? and
  the sort-into-buckets sibling of Sharp or Flat?, on the `accidental_sort`
  scaffold; built with crisp_notation `Triad(root, ChordQuality)`, the chord
  sounds on a correct drop. At 2★ a third basket — Diminished — joins (the lowered
  fifth), mirroring how Sharp or Flat? grows a Natural basket. SRI
  `chords.quality.<major|minor|diminished>`.
- **ABC import** (Song Book) — the importer takes pasted **ABC notation**
  (`scoreFromAbc`) alongside MusicXML / ChordPro / MIDI, stored as MusicXML like
  the rest. Opens the large public-domain ABC folk-tune libraries; the tune's
  `T:` line seeds the title.
- **Concert Pitch** (new **Transposing** module/corner) — read a written note
  for a **B♭ trumpet / E♭ alto sax / F horn** and name the concert pitch that
  actually sounds; crisp_notation's `transposeBy` computes the exact letter. The B♭
  instruments alone for beginners, E♭ and F added at 2★. A skill nothing else in
  the app covers. SRI `transpose.<instrument>.<written-step>`.
- **Write It for the Instrument** (Transposing) — the **inverse** of Concert
  Pitch: a **concert pitch** (what sounds) is shown on the staff; name the note a
  B♭/E♭/F instrument must **read** to produce it (`transposeBy` in the opposite
  direction). B♭ alone for beginners, +E♭/F at 2★; a correct answer plays the
  concert pitch. Together the two games drill both directions of transposition.
  SRI `transpose.<instrument>.write_<concert-step>` — a distinct leaf, so the two
  games never overwrite each other's SM-2 items.
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
  CrispFXR / voicelab. A **bidirectional notation bridge** links it to reading:
  Tracker → Score renders the selected channel as a live `StaffView` "score view"
  (held runs → tied notes, bar-split); Score → Tracker imports a melody back onto
  the grid (partial — quantize + top-note + pentatonic snap), round-trip tested.
  **Studio depth:** a per-channel instrument picker (additive + chiptune), a
  **drums** channel (drum-row grid), **song mode** (4 pattern slots A–D + an
  editable order-list + a song-length playhead), and **per-note dynamics**
  (long-press → soft "ghost" notes). Sandbox, no stars. (Mic capture is
  device-only; the DSP + assign→play path are unit-tested headlessly.)
- **Module formats & cross-format converters** (Tracker, `core/audio/mod/`) — the
  Tracker speaks the classic tracker file formats, all in **pure Dart** (web-safe,
  no native deps). **Readers** for ProTracker `.mod`, Scream Tracker 3 `.s3m`,
  FastTracker 2 `.xm` and Impulse Tracker `.it` — the hardest part, IT's IT214/215
  variable-bit-width sample **decompression**, was pinned by an oracle round-tripped
  **44/44 against libxmp's `itsex.c`** before a line of Dart was written.
  **Writers** for all four. A format-neutral **`ModuleDoc` hub** (pitch as MIDI so
  notes keep their pitch across formats, PCM normalized to ±1) turns the readers and
  writers into a **complete N×N converter matrix — any of {mod,s3m,xm,it} → any of
  {mod,xm,s3m,it}** (`parseAnyModule` sniffs by signature; conversion carries notes/
  instruments/volume/samples/structure, dropping per-cell effects in v1). Every
  codec was built the same disciplined way — a hand-authored, self-verified golden
  fixture (committed, license-clean) + a skip-if-absent live test over a real
  module, with one sub-agent implementing one file against a written contract. Also
  exposed as **headless CLIs** (`bin/modinfo.dart` dumps any module; `bin/modconv.dart`
  converts between formats and extracts samples to WAV — "steal an instrument" from
  the shell), Flutter-free like `bin/listen.dart`. In the app: MOD + MIDI
  import/export via a `file_selector` menu (the MIDI↔MOD hub reuses crisp_notation's
  Score bridge — no external converter).
- **Loop Mixer — beatbox + jam along** (composition, ladder slice 10) — the
  mic closes the circle twice more. **Beatbox a beat:** count-in, 2 bars of
  "boom-ts-pss" into the mic, and it comes back as a teal drum card — onset
  detection + kick/snare/hat classification (`beat_capture.dart`) on new
  rms/zero-crossing-rate features every `PitchReading` now carries, with
  thresholds calibrated against the app's own synth drums through the real
  detector and an acceptance test that a synthesized beatbox reconstructs
  the exact pattern. **Jam along:** the groove keeps playing while the mic
  listens (platform echo-cancel + a headphones hint); every note you play or
  sing lights up green (tone of the sounding chord — progression-aware),
  amber (pentatonic) or red — the loop mixer as a backing band that tells
  you when you fit.
- **Loop Mixer 2.0 — the groovebox ladder** (composition) — the v1 toy grew
  into an instrument in seven shipped slices (engine v2 → sing-a-track), all
  behind the same five-cards kid surface. **Feel:** a swing slider (off-eighth
  delay on an exact boundary grid), per-card A/B/C pattern variants (incl. a
  euclidean/Bjorklund drum groove), per-card levels, and an automatic drum
  fill every 4th loop, swapped in at the loop seam where the downbeat kick
  masks it. **Harmony:** a progression lane (I–V–vi–IV · I–IV–V–I · vi–IV–I–V)
  turns the 2-bar vamp into a 4-bar song — bass and chords re-voice per chord
  from chord-tone shapes (`ChordFollower`), melody/sparkle stay pentatonic
  (axis progressions absorb it) — verified end-to-end by rendering the bass
  and reading it back with `bin/listen.dart` (every bar's root/root/fifth/root
  detected exactly). **Notation:** a score panel engraves the leading track
  live via crisp_notation (`groove_notation.dart` — cells → 4/4 bars, greedy
  durations). **Keep it:** the whole groove is one small `GrooveSpec` value —
  a serverless `KU1.…` share token (copy/paste anywhere, defensively parsed)
  plus desktop WAV export. **Generativity:** infinite mode re-renders a
  seeded variation at every seam (hats breathe, snare ghosts, pentatonic
  melody ornaments; the kick never moves). **The mic:** *sing a track into
  existence* — count-in, 2-bar capture, the MPM pitch trace quantized to the
  step grid, octave-normalized and pentatonic-snapped (`groove_capture.dart`),
  and the child's own melody becomes a sixth card: toggleable, mixable,
  engraved as sheet music, carried inside the share token. Deep pattern
  *editing* is deliberately left to the Tracker (one grid editor in the app);
  beatbox→drums + AEC jam mode remain on the roadmap as slice 10.
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
- **Melody doodle** (composition) — Colour Melody's **gesture** twin: drag a
  freehand line across the box and it *becomes* a tune. The contour is quantised
  to one C-pentatonic note per beat (a column averages its points, so a scribble
  reads as its overall height; the top of the box is the highest note; untouched
  beats stay rests) and renders live to a **real `Score`** underneath. Beat guides
  and a coloured dot per quantised beat show the line turning into notes as you
  draw, and a note sounds only when the drag crosses into a new beat. A sandbox —
  no stars. For the youngest: "draw music" before you can tap a grid.
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

## Agent coordination board — shipped log (chronological)

These are the `✅ idle / SHIPPED` entries that accumulated on the top-of-
[PLAN.md](PLAN.md) coordination board as parallel agents finished work. Moved
here verbatim (2026-07-17) to keep PLAN.md focused on pending work. Newest-ish
first, as they sat on the board.

- **opus (articulation)** · ✅ **SHIPPED — "Read the Mark" articulation minigame**
  (`cedf4da`, Noten lesen). Fills a real gap: ties/slurs + note values were
  covered, but the note-attached articulation marks had no reading game. A
  binary staff-read on the `step_skip` scaffold — one note carries an
  articulation glyph (staccato dot / accent wedge, drawn by crisp_notation
  `layout_marks`); the child matches it to its name. Binary at 1★ (Staccato vs
  Accent), full four-way (+Tenuto/Marcato) from 2★; a correct answer sounds the
  note (short for staccato). `GameInfo` in note_reading + `kStarThresholds`
  bracket + EN/DE ARBs. SRI `reading.articulation.<name>`. 4 tests (incl. an
  assertion that the rendered `StaffView` actually carries the glyph). Whole-
  project analyze clean.

- **opus (aec-res-c)** · ✅ **SHIPPED — residual echo suppression ported to the
  native C engine** (`b3bf617`). Completes the native AEC algorithm stack (DTD +
  RES, both now in the C engine, all headlessly verified). `src/aec_dsp.{c,h}`
  gained an `AecRes` (a port of the Dart `ResidualEchoSuppressor`, reusing the
  DSP's own `aec_fft`/`ifft` and the same overlap-save Wiener framing with a
  DTD-gated leakage estimate); FFI-bound as `AecRes` in `lib/aec_dsp.dart` with
  an offline cross-check (RES deepens echo-only ERLE >3 dB past the linear
  filter). Wired **opt-in** into the engine block loop (`aec_engine_set_res` /
  `AecEngineFfi.setRes`), its leakage gated on the DTD's single-talk decision;
  needs a distinct output buffer (can't run in place). Headless engine test +
  whole native suite 10/10 via `build.sh`. Remaining native AEC is on-device
  only (milestone e): app opt-in via `setDtd`/`setRes` + real-hardware tuning.

- **opus (aec-engine-dtd)** · ✅ **SHIPPED — DTD wired into the native engine
  block loop** (`c11ddc7`). The DTD was ported to the C DSP core (`f7487fd`) but
  nothing used it; now `aec_shim.c`'s `engine_run` (the shared core the realtime
  duplex callback AND the headless pump both run) drives it per block — read
  `aec_dtd_freeze` → `aec_dsp_set_adapt` → process → `aec_dtd_update`. Opt-in via
  a new `aec_engine_set_dtd()` (default off — a DTD hurts without a clean
  convergence window, so this keeps the existing continuous-double-talk engine
  test green); FFI-bound as `AecEngineFfi.setDtd(bool)`. Headless double-talk
  test in `test/aec_engine_test.dart` (converge→double-talk through the pump,
  DTD-on near-end error <0.7× DTD-off). Whole native suite 8/8 via `build.sh`.
  All in `native/aec/` (out of app CI). Remaining native AEC: port RES to C; app
  opt-in via `setDtd` (milestone e, needs on-device tuning).

- **opus (aec-res)** · ✅ **idle / SHIPPED — residual echo suppression**
  (`15a6d62`). **The patent-free AEC algorithm roadmap is COMPLETE (DTD + RES).**
  `ResidualEchoSuppressor` (`aec_offline.dart`): a Wiener-style spectral
  post-filter on what the linear filter leaves, reusing the canceller's own
  overlap-save framing (2·blockSize `[prev;cur]` frame, spectrally gained, keep
  the last block — no window/COLA bookkeeping). Per bin the residual echo is
  `λ(k)·|Ŷ(k)|²` with the echo leakage **λ learned only on far-end single-talk
  (DTD-gated)** — during double-talk the near-end inflates the residual and would
  drive λ, and the suppression, far too high; a `gainFloor` bounds attenuation.
  Opt in: `cancelEcho(residualSuppress:)` / `StreamingEchoCanceller` /
  `bin/aec.dart --res` (compose with `--dtd`). **Measured: echo-only segmental
  ERLE 39.3 → 54.6 dB (+15.3), double-talk SI-SDR unchanged (15.8 vs 15.9, −0.1)
  — deeper echo suppression without chewing the voice.** 25 tests (5 new). No
  app / Workshop / native plugin touched.

- **opus (aec-dtd)** · ✅ **idle / SHIPPED — double-talk detector** (`a10d6bd`,
  patent-free AEC roadmap item 1). The linear core kept adapting on near-end
  speech; a DTD freezes it while the near-end is present. **`DoubleTalkDetector`**
  (`aec_offline.dart`) uses a normalized-correlation statistic
  `corr(mic, echoEst=W·x)` — ≈1 on far-end single-talk, drops on double-talk —
  needing no echo-path-gain threshold (unlike Geigel); warmup guard + hangover.
  Additive **`EchoCanceller.process(..., {bool adapt = true})`** gates the NLMS
  update (default true ⇒ C port + existing callers untouched; `EchoCanceller` is
  CLI/test-only, jam uses the native engine). Wired into
  `cancelEcho(doubleTalkDetect:)`, `StreamingEchoCanceller`, `bin/aec.dart --dtd`.
  **Result: double-talk SI-SDR 8.8 → 15.9 dB (+7.1 dB vs linear)**, echo-only
  cancellation unchanged. 20 tests (4 new). No app / Workshop / native plugin
  touched.

- **opus (aec-metrics)** · ✅ **idle / SHIPPED — AEC quality metrics + thorough
  tests** (`1e0bc8c`). Patent-free metrics in `lib/core/audio/aec_offline.dart`:
  **segmental ERLE**, **convergence time**, **SI-SDR** (scale-invariant SDR,
  Le Roux 2019 — the gain-invariant double-talk fidelity metric), + an
  `AecMetrics.measure/report` bundle. Explicitly NOT PESQ/POLQA (license/patent
  encumbered); AECMOS is MIT but native-ORT-only (our pure-Dart
  `onnx_runtime_dart` lacks conv/GRU ops). `bin/aec.dart --selftest` reports the
  full set on the standard converge→double-talk scenario. **16 tests** (broadband
  convergence + exact delay, small block size, no-NaN, far-end-silence exact
  passthrough, SI-SDR identity/scale-invariance/monotonicity, streaming≡batch
  w/ refDelay, flush padding, empty-input). Docs: patent-free rationale in
  `AEC_TIER3B.md`. No app/Workshop/native-plugin touched.

- **AEC — what's left (unclaimed; verification now UNBLOCKED).** The patent-free
  *algorithm* roadmap is done (DTD `a10d6bd` + RES `15a6d62`), but **both live only
  in the Dart/CLI path** (`aec_offline.dart`); the app's jam mode runs the native C
  engine, which still has neither.
  ✅ **opus (next): fixed the native verify harness** (`native/aec/build.sh`
  `dart test` → `flutter test` — the tests import `package:flutter_test`, so
  `dart test` errored "Could not find package test"; the C build was fine). **The
  6-test ERLE cross-check now runs green on this Mac**, so the port below is finally
  verifiable. Two open items, in value order:
  1. **Port DTD (+ later RES) to `native/aec`** (`src/aec_dsp.c` + the shim's block
     loop) so the app's jam mode gets the +7 dB double-talk protection. Suggested:
     do **DTD first** (simpler, higher value), RES second. Add a `dtdEnabled` +
     hangover/block-counter to `AecDsp`, compute `rho = dot(mic, echoEst)/√(mm·ee)`
     (echoEst = the predicted echo `yRe[b+i]`), and gate the NLMS update
     (`aec_dsp.c` ~L209–231) when frozen. ⚠️ **Fidelity trap:** match
     `DoubleTalkDetector` (aec_offline.dart) EXACTLY — its `update()` runs the
     block-counter + hangover **decrement every block**, incl. far-end-silent
     ones, whereas `aec_dsp_process` **returns early** on the far-end VAD (L190–196);
     do the DTD state bookkeeping BEFORE that early return or the freeze timing
     drifts from the Dart reference. Keep DTD **off by default** so the existing
     default-`adapt` cross-check still matches; add a NEW test asserting
     native-with-DTD ≈ Dart-with-DTD on a double-talk scenario. Verify with
     `bash native/aec/build.sh`. Keep CI-safety (analyzer exclusion, app green
     without the plugin).
  2. **(e) on-device tuning** — the real duplex path on iOS/Android hardware
     (mic permission, AVAudioSession category, latency/ring). Needed before jam
     AEC is real at all; see `docs/AEC_TIER3B.md`.

  Verify either with the `bin/aec.dart` harness (`--selftest`, `--dtd --res`) and
  the BlackHole rig. Same patent-free family as SpeexDSP MDF / WebRTC AEC3 (read
  for technique, don't vendor unless licence + tree stay clean).

- **opus (aec-cli)** · ✅ **idle / SHIPPED — AEC streaming CLI** (`dafacb1` D1,
  `afbe4ea` D2). Test echo cancellation over files/pipes headlessly — the
  pure-Dart `EchoCanceller` the native Tier-3b core is a cleanroom port of, so
  no device/FFI needed. **D1:** Flutter-free `lib/core/audio/aec_offline.dart`
  (`estimateEchoDelay`, `cancelEcho(mic,ref)→cleaned+ERLE+delay`,
  `StreamingEchoCanceller` for interleaved stereo PCM16 → cleaned mono, running
  ERLE, buffers partial frames), 4 tests (tail ERLE >20 dB, near-end preserved
  under double-talk, delay recovery, streaming≡batch byte-equality). **D2:**
  pipe-first `bin/aec.dart` — `--selftest` (band+instrument+echo → PASS: ~48 dB
  echo-only ERLE, instrument survives), `--mic/--ref/--out` files, `--stdin`
  interleaved-stereo mic|ref → cleaned mono stdout (or `--detect` notes);
  deduped `bin/listen.dart`'s `--aec` onto the shared core. Verified over a real
  OS pipe (stereo gen → `aec --stdin` → `listen --stdin` reads the instrument,
  echo gone). Docs: streaming section in `AEC_TIER3B.md`. The offline analogue
  of the BlackHole rig, runnable in CI. **No app screens / ARBs / Workshop /
  native plugin touched.**

- **opus (parity)** · ✅ **idle / SHIPPED — keyboard-first nav in Select mode**
  (`b26a6b5`, last small Cause-2 item). Select-mode A–G keys jump the selection to
  the next note on that pitch (wrapping, accidental-insensitive) via
  `ScoreDocument.selectNextOfStep(Step)` — Insert enters notes, Select navigates
  them. **With this the WORKSHOP_PARITY arc + all its polish are shipped**; the
  only open items are "if ever wanted" (categorized insertion palettes; multi-
  select/rest inspector depth; grace-note LIST beyond one run — a library ask).
  ✅ **PDF export SHIPPED** (`e0954bd`, bucket G's last open
  item). **No library change** — `SystemLayout.layout` *is* a `ScoreLayout` and
  `renderLayoutToPng` takes one, so `layoutPages(score, settings, metrics:)`
  line-breaks + paginates, each `PositionedSystem` rasters to a PNG (through the
  app's painter → correct Bravura glyphs, 3× for print), and the `pdf` package
  places each at its exact staff-space position on an A4 box (staff-spaces →
  points via one spatium). Raster-per-system because the SVG path embeds
  `@font-face` text the pdf pkg can't parse + Bravura is CFF/OTF (TTF-only
  embedder). `+pdf ^3.11.0`, `lib/features/workshop/export/score_pdf.dart`,
  "PDF (print)" in `kExportFormats`, `test/score_pdf_test.dart` (valid header +
  real pagination + size scaling, under `runAsync`). Now: Select-mode letter keys
  jump the caret instead of no-op'ing.
- **opus (parity)** · ✅ **SHIPPED — value strip un-dual-purposed**
  (Cause 2's other grievance). The strip stays deliberately dual-purpose on
  **Sandbox** (arm the next note *and* fix the selected one — forgiving, what kids
  expect; unchanged, no regression). **Studio** honours the input mode instead:
  *insert* arms without silently rewriting the selection, *select* applies the
  pick to the selection. One `_pickAppliesToSelection` getter gates
  `_pickValue`/`_toggleDot`/`_pickAccidental`; arming always happens so the armed
  glyph stays in step. Widget tests pin all three behaviours (via barCount: a
  selected quarter → whole spills a bar). **Cause 2 is now fully addressed.**
- **opus (parity)** · ✅ **SHIPPED — inspector multi-select** (polish).
  The Studio inspector now edits a **multi-note selection**, not just a single
  note (the ⌃ palette's old Cause-3 limitation): articulation/tie chips reflect
  "all selected have it" and toggle the whole selection; dynamic/ornament
  dropdowns show the shared value (or blank when mixed) and set all; the
  single-anchor grace / change-here buttons disable for a multi-selection. Rests
  now read out instead of showing the empty hint. Widget test drives a 2-note
  selection into the inspector. `screens/composition_workshop_screen.dart` only.
- **opus (parity)** · ✅ **SHIPPED — Sandbox/Studio shelf toggle**
  (`5d467dc`, the two-shelves capstone). One `_Shelf { sandbox, studio }` switch
  (⋮ menu, default Sandbox): Sandbox hides the Studio-tier controls (V1/V2 voice
  toggle, Insert/Select mode toggle, inspector) → simple kid surface; Studio
  reveals them all together. Leaving Studio resets input mode→insert,
  inspector→off, active voice→0. **This closes the Studio-shell arc** — voice 2,
  the inspector (Cause 3), input modes (Cause 2) and now the shelf that unifies
  them. EN/DE; widget tests (Sandbox hides / Studio reveals; the depth-control
  tests enter Studio first). **The WORKSHOP_PARITY.md arc is now substantially
  complete** (A–G + the two shelves); remaining is polish — richer inspector
  (multi-select/rests/bar attrs), insertion palettes, keyboard-first nav in
  select mode, page/print view, PDF. Next agent: see `WORKSHOP_NEXT_HANDOVER.md`.
- **opus (parity)** · ✅ **SHIPPED — Studio shell Causes 2+3.** **Cause 2
  (input modes)** `8526bc0`: an `_InputMode { insert, select }` on the screen,
  default insert (= today). Select mode makes empty-staff taps deselect (not
  place) and letter keys no-op (`_onStaffTap`/`_onMpStaffTap`/`_handleKey` gate on
  it); tapping a note still selects, the piano still places. Insert⇄Select toggle
  (icon+label) in the top bar. EN/DE; widget test. **Remaining Studio work:** a
  real **Sandbox/Studio shelf toggle** (one switch that reveals the Studio-tier
  surfaces — inspector, mode toggle, future insertion palettes — instead of each
  being gated separately), richer inspector (multi-select / rests / bar
  attributes), and categorized insertion palettes. **The Workshop parity arc's big
  buckets (D notation-depth, F playback, Studio shell) are now all substantially
  shipped.** — Cause 3 (inspector) SHIPPED below:
- **opus (parity)** · ✅ **SHIPPED — Studio shell Cause 3 (inspector)**
  (`6306151`). A selection-driven properties panel (`WORKSHOP_PARITY.md` Cause 3):
  an **opt-in** side panel (⋮ menu toggle, OFF by default → Sandbox unchanged) that
  reflects/edits the selected note — articulations/tie (FilterChips), dynamic +
  ornament dropdowns, buttons to the grace + change-here dialogs; reuses the `_doc`
  mutators. Canvas `Expanded` became `Row[canvas, panel]`. The ⌃ palette stays.
  EN/DE; widget test (off-by-default → toggles on → shows controls). **Remaining
  Studio work — Cause 2 (input modes):** an explicit insert-vs-select state machine
  (today staff-taps always place; `_onElementTap` already selects, so the piece is a
  "select mode" that stops empty-staff placement + a status-line mode + keyboard-
  first entry). Also open: richer inspector (multi-select, rests, bar attributes),
  a real Sandbox/Studio shelf toggle. ✅ **voice 2 SHIPPED** (`bb6b7d0`):
  `Measure.voice2`, a sibling `_v2` stream sharing the bar grid via the `_elements`
  active-voice getter (mutation sites untouched); `_withVoice2` reflow+stamp
  (byte-identity fast path); V1/V2 toolbar toggle; MusicXML round-trips. ✅ **mid-bar
  clef SHIPPED, fully lossless** (`12404e1`/`854ab25` + crisp_notation writer
  `3c1b8bd`).
- **opus (next)** · ✅ **idle.** Worktree `../mus-next`, branch
  `feature/workshop-next`. All shipped & recorded in [HISTORY.md]: Workshop tempo
  marks · grace notes · playback bucket F · multi-part playback · voice-2 playback ·
  practice speed · count-in + loop-a-selection; Song Book **Sing along + Play along**
  (`chartFromScore`) with length-scaled stars; **Melody doodle** game; and the
  **native-AEC verify-harness fix** (`eba8c4d`, `build.sh` → `flutter test`) that
  unblocks the AEC C port (top item in the scoped block above). My feature lane is
  exhausted — remaining work is in the scoped "🎯 Remaining work" block at the top.

- **opus (groove-export)** · ✅ **idle / SHIPPED — Groove → Song Book / MusicXML**
  (`docs/LOOP_MIXER_FOLLOWUPS_HANDOVER.md` §A; `3c816ab` A1, `a7c3554` A2+A3).
  The Loop Mixer's share sheet now saves the groove as a **real multi-part
  score** — the payoff of the toy and the on-ramp to the Workshop. **A1:** pure
  `grooveParts()` in `groove_notation.dart` — enabled pitched tracks
  (voice·melody·chords·sparkle·bass) → one `Score` each (bass clef for bass) →
  `MultiPartScore`; drums/beat skipped (no percussion staff yet). **A2:** share
  sheet "Save to Song Book" → `multiPartToMusicXml` → `UserSongsService.addSong`
  (gated on a pitched track). **A3:** "Export sheet music (MusicXML)" desktop
  save. l10n de/en (`loopMixerSaveSongBook/ExportMusicXml/SaveTitle`). Tests:
  8/8 groove_notation + 12/12 loop_mixer (multi-part round-trip through the
  Song Book). **No Workshop files touched.** Only §B (native-AEC jam grading)
  of the handover remains unclaimed.

- **opus (jam-grading)** · ✅ **idle / SHIPPED — Groove jam: native-AEC grading
  ("the band listens back")** (`docs/LOOP_MIXER_FOLLOWUPS_HANDOVER.md` §B;
  `915a17a` B1, `5e99e84` B2+B3). This closes the Loop Mixer follow-ups handover
  — **both §A and §B done.** **B1:** pure-Dart `lib/core/audio/loop_reference.dart`
  (`LoopReferenceScheduler`: loop PCM → real-time reference windows, seam wrap +
  phase-preserving swap-at-downbeat, `barAt`), 6 tests. **B2:** jam mode picks the
  Tier-3b `AecEngine` (`createNativeAecEngine`) when present — the engine plays
  the loop PCM we feed it AND cancels it, so the jamFit colour grades the player
  not the speaker; a 50ms reference pump (2205 samples/tick = the 44.1k drain)
  keeps the ring fed; live edits re-feed the scheduler at its seam. Graceful
  fallback to the shipped `echoCancel` path when no plugin (web / device open
  fails). `aecFactory` injection drives it headless. **B3:** AEC start hint +
  a trust caption under the live note ("band cancelled — this grades you" vs the
  headphones reminder). CI-safe: `dart:ffi` stays out of web (conditional
  export), plugin stays analyzer-excluded, app green with plugin absent. Tests:
  14/14 loop_mixer (fake-AEC round-trip: reference pushed + synth A4 on the
  cleaned stream graded as A4) + 6/6 loop_reference; whole-project analyze clean.
  ⚠ **On-device pump tuning (ring latency) is milestone (e) — needs hardware, not
  verifiable headless.** Deferred-optional: "follow the melody" per-note grading
  via `PlayAlongEngine` (a moving-score highway over the groove) — its own effort.
  **No Workshop / AEC-plugin internals touched.**

- **opus (jam-follow)** · ✅ **idle / SHIPPED — Groove jam "follow the melody"
  (per-note grading)** (`9ff81c1` C1, `6af3d00` C2). Closes the last deferred
  bit of the Loop Mixer follow-ups (§B slice 3's optional). **C1:** pure
  `grooveChart()` in `groove_play_along.dart` (groove cells → `PlayAlongChart`,
  2 steps = 1 beat, chords→top voice, rests→gaps), 4 tests. **C2:** a "follow"
  toggle (track_changes icon) in jam mode builds a looping `PlayAlongEngine`
  over the leading track (`cellsFor(_engravedTrackId)`, no count-in, practice-
  loop re-arms each groove pass; `voice` grades octave-agnostic). Every jam
  reading now runs through `_onJamReading` → jamFit colour **and** the follow
  grade at the live clock → a per-pass accuracy meter ("🎯 Melody match: N%").
  Rebuilds on grid change, torn down on jam stop, works in either jam tier.
  `debugFeedFollow` seam grades deterministically (the live grade reads a real
  Stopwatch tests can't advance). l10n de/en (`loopMixerFollow` +
  parameterized `loopMixerFollowScore`). Tests: 24/24 loop_mixer + 4/4
  groove_play_along; whole-project analyze clean. **No Workshop / AEC internals
  touched.** The entire Loop Mixer follow-ups arc (§A, §B, follow-melody) is now
  done.

- **opus (parity)** · ✅ **idle / SHIPPED — mid-*bar* clef changes (`inlineClefs`)**
  (`12404e1` model + `854ab25` UI). Onset-addressed clef change *within* a bar
  (draws right before the anchored note), vs today's bar-*start* `clefChange`.
  Additive `_inlineClefs` id-anchor side-map → `Measure.inlineClefs`; the
  `_withInlineClefs` stamp accumulates each bar's tuplet-scaled onset and emits an
  `InlineClefChange` at the anchor (onset-0 skipped — that's a bar-start change);
  empty-anchor byte-identity fast path; `loadScore` recovers them (so **import**
  keeps mid-measure clefs). "Clef (mid-bar)" row in the change-here dialog, EN/DE.
  `test/inline_clef_test.dart` (9) + widget row-presence; affected suite green,
  analyze clean. ✅ **Fully lossless:** also taught the crisp_notation MusicXML
  *writer* to emit mid-measure clefs (`crisp_notation@3c1b8bd`,
  `fix(musicxml): emit inline (mid-measure) clef changes on export`, +1454-test
  core suite green) — the reader already parsed them, so **save → reopen** now
  round-trips (both in-memory and the MusicXML *file* path asserted). Closed the
  `workshop-musicxml-writer-gaps` blocker. **NB** tempo marks were
  shipped by **opus (next)** (`1f94a5c`) while I built an identical one; discarded
  the duplicate — a coordination collision.
- **opus (parity)** · ✅ **idle / SHIPPED — note ornaments (trill/mordent/turn)**
  (`194fa66` model + `5459e60` UI, suite **738 green**). Per-note `Ornament?`
  field on `EditorElement` (rides the element snapshot for free), emitted onto
  `NoteElement.ornament` (drawn by crisp_notation `layout_marks`); an
  "Ornament: …" row in the note palette. Round-trips. **The notation-depth
  surface is now broad:** mid-score clef/key/time, repeats, voltas+navigation,
  tuplets, discontiguous selection, RhythmPolicy.split, and ornaments — all on
  the flat model. **Remaining bigger gaps** (each its own effort): grace notes
  (a note carries a LIST of grace notes — a mini-editor), tempo marks (id-anchor
  stamp, feeds playback), mid-*bar* clef changes (`inlineClefs`), voice 2, the
  **Studio shell** (input modes + inspector, Causes 2+3), and **playback** (real
  transport + moving cursor). **A fresh agent should start from
  [`docs/WORKSHOP_NEXT_HANDOVER.md`](WORKSHOP_NEXT_HANDOVER.md)** — it scopes each
  remaining item, the id-anchor-vs-field pattern that built the batch, the
  byte-identity invariant, and the test conventions.

- **opus (tracker)** · ✅ **idle / SHIPPED — Tracker gaps filled (multi-agent).**
  3 pure-core sub-agents (against contracts + test suites I wrote) built
  `mod_bridge.dart` (Tracker↔MOD), `tracker_effects.dart` (arp/vibrato/slide DSP)
  and `tracker_notation.dart` (multi-part Tracker↔Score + chord split) — 22 tests,
  `ac12747`. I then integrated all shared-file wiring: **per-note effects** (cell
  menu) `28f2f83`, **MOD import/export UI** (file_selector) `ae484a9`, **multi-part
  score view** `d67cb56`, **gapless two-player swap** `df7e644`, and **MIDI
  import/export = the MIDI↔MOD hub** (via crisp_notation `scoreFromMidi`/
  `scoreToMidi`, no external converter) `8a80421`. ✅ **`.s3m` reader SHIPPED**
  `2860ce2` (golden oracle + real "Illustrious Fields"; agent-built against my
  contract+tests). ✅ **`.xm` reader SHIPPED** (`xm_module.dart` model+byte-spec +
  `xm_reader.dart` `parseXm` + golden oracle `test/fixtures/golden.xm` + real "The
  final support" 24ch/20pat/77ins live test; agent-built against my contract+tests;
  MSB-mask pattern unpack + delta-decoded 8/16-bit samples). ✅ **`.it` reader
  SHIPPED** (`it_module.dart` model+byte-spec + `it_reader.dart` `parseIt` + golden
  `test/fixtures/golden.it` + real "terrascape intro music" 8ch/17pat/12smp live
  test; agent-built against my contract+tests). Handles the mask-cache pattern
  unpack, uncompressed 8/16-bit (signed/unsigned/LE-BE/delta) AND **IT214/IT215
  compressed** samples — the variable-bit-width decompressor's exact algorithm was
  validated by a Python oracle round-tripped against **libxmp `itsex.c`** (44/44),
  and golden.it embeds validated compressed blocks so the hard path has a byte-exact
  target even though the real file is all-uncompressed. **Module reader set now
  complete: `.mod` · `.s3m` · `.xm` · `.it`.** ✅ **Cross-format converters —
  slice C1 SHIPPED** (`module_doc.dart` neutral hub model + `module_convert.dart`:
  `sniffModuleFormat`, `parseAnyModule` = unified importer, `docFrom{Mod,S3m,Xm,It}`
  adapters, `docToMod`/`convertToMod`). Any format → neutral `ModuleDoc` (pitch as
  MIDI, PCM normalized ±1, 1-based instruments) → `.mod`. v1 drops per-cell effects
  (cross-format effect table = follow-up); notes/instruments/volume/samples/
  structure convert cleanly. Test: 4 goldens through the hub + XM→MOD round-trip +
  live wild files. ✅ **XM writer + convertToXm SHIPPED** (slice C2): `xm_writer.dart`
  `writeXm` (byte-inverse of `parseXm`: header, MSB-mask packing, instrument/sample
  headers, delta-encoded 8/16-bit) + `docToXm`/`convertToXm` — now **mod2xm /
  s3m2xm / it2xm** work (xm2mod already did via convertToMod). Verified by
  write→parse round-trips (golden + hand-built multi-channel/16-bit) + mod→xm &
  it→xm hub conversions. ✅ **S3M writer + convertToS3m SHIPPED** (slice C3):
  `s3m_writer.dart` `writeS3m` (paragraph-aligned layout, parapointer patch pass,
  signed PCM, "what"-byte pattern packing) + `docToS3m`/`convertToS3m` → **mod2s3m /
  xm2s3m / it2s3m**. Round-trip verified (golden + hand-built loop/multi-channel) +
  mod→s3m & it→s3m hub conversions. ✅ **IT writer + convertToIt SHIPPED** (slice
  C4): `it_writer.dart` `writeIt` (sample-mode, absolute-offset layout + patch pass,
  uncompressed signed 8/16-bit, channelvar+mask packing) + `docToIt`/`convertToIt`.
  Compressed source samples write back uncompressed (PCM intact). **Converter matrix
  now COMPLETE — full N×N: {mod,s3m,xm,it} → {mod,xm,s3m,it}.** Verified by golden +
  hand-built round-trips + mod→it & xm→it hub conversions. **Next: "borrow a sample
  from a module"** (readers already expose normalized PCM — wire a module→sample→
  SampleInstrument picker); the headless **CLI tools** (§H — modinfo/modconv/render);
  optional IT214/215 *compressor* + a cross-format effect table (v1 drops effects).
  📋 **Full idea backlog —
  codecs, FX (crispaudio/CrispFXR/voicelab + OpenMPT), sampling, notation, Studio
  depth — in [`docs/TRACKER_IDEAS.md`](TRACKER_IDEAS.md); the FX effort in
  [`docs/FX_HANDOVER.md`](FX_HANDOVER.md).**
- **opus (tracker)** · ✅ **idle / SHIPPED — `.mod` import/export codec.** Pure-Dart
  ProTracker codec in `lib/core/audio/mod/` (model+contract `mod_module.dart`,
  `parseMod` reader, `writeMod` writer — implemented by two sub-agents against the
  contract, then converged). **Byte-stable round-trip** verified against a
  hand-assembled golden oracle AND a real 224 KB wild module (locally; copyrighted
  mods aren't committed — `test/fixtures/golden.mod` is the license-clean fixture,
  and `test/mod_codec_test.dart` round-trips any `.mod` dropped in). 6 tests green.
  Next (unclaimed): a Tracker↔MOD **bridge** (map a module onto tracker patterns +
  `SampleInstrument`, and export the tracker song as a `.mod`) — lossy, needs the
  8-step grid ↔ 64-row mapping decisions. Below: the rest of the Tracker (shipped).
- **opus (tracker)** · ✅ **idle / SHIPPED — Tracker (pattern sequencer).** Dual-audience
  tracker (ModEdit/FT2/ST3/IT spirit, touch-first, Sandbox/Studio two-skins-over-
  one-model) built ON the shipped Loop Mixer engine (`mixStems` +
  `loop_engine.dart`). Full plan: [`docs/TRACKER_HANDOVER.md`](TRACKER_HANDOVER.md).
  Worktree `../mus-tracker`, branch `feature/tracker`.
  ✅ **Slice 0 SHIPPED** (`98cdb05`): pure-Dart `TrackerEngine` (additive), 13
  tests. ✅ **Slice 1 SHIPPED** (`775fe03`): the Sandbox grid screen (instrument
  tabs + pentatonic piano-roll + looping playback + playhead), registered sandbox
  `GameInfo 'tracker'` in composition, EN/DE, 4 tests. ✅ **Slice 2 SHIPPED**:
  sfxr chiptune instruments — focused pure-Dart port of `crispaudio`'s SynthEngine
  into **`lib/core/audio/crisp_dsp/sfxr.dart`** (+ `test/sfxr_test.dart`), a
  `SfxrInstrument` on the `TrackerInstrument` seam synthesized per-note at pitch,
  and a live `zap` chiptune channel in the default band. **Settled hot files:**
  `game_registry.dart`, both ARBs. ✅ **Slice 4a SHIPPED** (`449bd6f`): sample DSP
  in `crisp_dsp/` (resampler + granular pitch-shift + formant-shift ports from
  `crispaudio`) + `SampleInstrument` + `VoiceEffect` palette (chipmunk/monster/
  deep via formant, robot via ring-mod+bitcrush — pitch-stable so samples stay in
  tune). ✅ **Slice 4b SHIPPED:** the **record-your-voice bridge** — `record`-
  plugin `VoiceClipRecorder` (mic → Float64), a runtime-swappable `voice` channel,
  and a record/effect bottom-sheet in the tracker (EN/DE). ⚠️ **Mic path is
  device-only** — verified via the tester seam (inject a synthetic clip); real
  mic needs an on-device run. ✅ **Slice 5a SHIPPED (notation bridge,
  Tracker→Score):** `tracker_notation.dart` `trackerChannelToScore` (held runs →
  tied notes decomposed to standard values, split at 4/4 bar lines) + a StaffView
  "score view" panel toggled from the app bar (the selected channel as notation).
  ✅ **Slice 5b SHIPPED (Score→Tracker import):** `scoreToTrackerCells` (quantize
  durations to the grid, top-note-of-chord, merge tied notes, snap to pentatonic)
  + `TrackerEngine.setChannelCells` + a "Load a tune" app-bar action importing a
  built-in demo melody into the melody channel. Round-trip (Tracker→Score→Tracker)
  is unit-tested — the bidirectional bridge is complete.
  ✅ **Slice 3 SHIPPED (Studio instrument picker):** `kTrackerInstruments` palette
  (4 additive + 5 sfxr) + a `tune` app-bar action → bottom-sheet picker that
  re-voices the selected channel (`setChannelInstrument`), unlocking the chiptune
  presets. ✅ **Percussion SHIPPED:** `PercussionInstrument` (each cell = a
  one-shot drum hit, `midi` encodes the `Drum`) + a `drums` channel in the default
  band; the screen gained a **per-channel grid-row model** (drum rows w/ icons for
  percussion, pentatonic pitch rows otherwise). ✅ **Workshop↔Tracker handoff
  SHIPPED:** the "Load a tune" action is now a **song picker over the shared
  `kSongs` book** (Alle meine Entchen / Twinkle / …) — import a real tune's opening
  bar onto the grid to remix (via `scoreToTrackerCells`; partial by design). ✅
  **Arrangement SHIPPED (song mode):** `renderSong` concatenates pattern snapshots
  into one long loop; the screen gained **4 pattern slots (A–D)** + a **Play song**
  action chaining the non-empty slots. ✅ **Song mode v2** (`6afdaf2`): editable
  order-list (A A B A) + a song-length playhead. ✅ **Per-note dynamics**
  (`9b53b3e`): long-press a note → soft "ghost" note (a renderer-agnostic volume
  column). ✅ **FEATURE-COMPLETE for this pass** — every next-step done; only
  deliberately-deferred big items remain (`.mod`/`.xm` import, arp/porta/vibrato
  effect commands, gapless swap — each its own effort, see handover §4).
  **opus (tracker) → idle.** Handover:
  [`docs/TRACKER_HANDOVER.md`](TRACKER_HANDOVER.md).
- **opus (parity)** · ✅ **idle / SHIPPED — notation-depth batch (voltas/nav, tuplets, discontiguous selection, RhythmPolicy.split).**
  Working through the tracked roadmap in
  [`WORKSHOP_PARITY.md`](WORKSHOP_PARITY.md) §"Notation-depth roadmap": **(1)
  voltas + navigation** (D.C./D.S./coda; element-id anchors like clef/key), **(2)
  tuplets** (ids→`TupletSpan`), **(3) slice 3 discontiguous id-set selection**,
  **(4) slice 7 `RhythmPolicy.split`**. Each = its own commit + board update;
  each touches `score_document.dart` then `composition_workshop_screen.dart`
  (`_paletteButton`) + ARBs. **(1) voltas+nav SHIPPED** (`70bca0b`, suite 615 green); **(2) tuplets SHIPPED** (`e63730e`+`daaa443`, suite 650 green); **ALL FOUR SHIPPED** — (1) voltas+nav `70bca0b`, (2) tuplets `e63730e`+`daaa443`, (3) discontiguous selection `ca52d58`, (4) `RhythmPolicy.split` `7ffe193`+`5fda285`. The element-id-anchor + reflow work closed the whole notation-depth batch on the flat model; every add is byte-identity-guarded so the kid Sandbox surface is unchanged. **Idle.**
- **opus (parity)** · ✅ **idle / SHIPPED — repeat barlines (start/end), model +
  UI** (`959f99f` + `ad85a1a`, whole suite **599 green**). Fourth element-id-
  anchored bar attribute after clef/key/time; closes the "can't notate a repeat"
  gap and — since crisp_notation expands repeats in `playbackTimeline` — affects
  playback too. Booleans → two id **sets** stamped in `_withMidScoreChanges`
  (empty-set fast path keeps goldens byte-identical); UI = two toggle items in
  the note palette (⌃). Round-trips through MusicXML. `score_document.dart` +
  `composition_workshop_screen.dart` (`_paletteButton` only) settled again.
- **opus (games)** · ✅ **idle / SHIPPED — new-minigame + creative-mode sweep.**
  Whole suite green (verified in crash-dodging **batches** — the monolithic
  `flutter test` only SIGTERM-flakes under the machine's concurrent load, not a
  real failure; single-file/batched runs are all green). 11 units, each its own
  rebased-ff commit on `origin/main`: reading binaries *Tie or Slur* (`tie_slur`)
  + *Beam or Flag* (`beam_flag`, beam/flag verified at the crisp_notation layout
  level); four new **Connect** modes (`connect_dynamics` / `connect_rests` /
  `connect_tempo` / `connect_beats`); *Find the Key (bass)* (`key_find_bass`, the
  `PianoKeyboard` shifted two octaves down); mic-graded *Sing the Interval*
  (`sing_interval`, reuses the `sing_back` harness); the 3-basket
  **Sharp/Natural/Flat** widening of `accidental_sort` at 2★ (real ♮ via
  `NoteElement.showAccidental`); *Triad or Seventh?* (`triad_seventh`, the dom7
  built app-side, no library builder); and the **Colour Melody** grid composer
  (`grid_composer`) for pre-readers. **Hot shared files touched (all settled):**
  `game_registry.dart`, `core/tuning.dart`, the ARBs, `connect_line_screen.dart`,
  `accidental_sort_screen.dart`, `key_find_screen.dart`. **Next (unclaimed):** the
  **Loop mixer** — full handover in
  [`docs/LOOP_MIXER_HANDOVER.md`](LOOP_MIXER_HANDOVER.md).
- **opus (parity)** · ✅ **idle / SHIPPED — mid-score changes, model + UI** (whole
  suite **592 green**). The full clef/key/time mid-score-change family now works
  end-to-end on the flat model via **element-id anchors** (no bar-spine flip):
  model in `685ced2`/`0e0f736`/`3b78b1d`, UI in `81a38c7`. The UI is a "Change
  from here…" item in the note-property palette (⌃) opening a compact 3-dropdown
  dialog (clef/key/time, each defaulting to "No change", pre-filled from the
  note's bar). `score_document.dart` settled; `composition_workshop_screen.dart`
  touched only in `_paletteButton` + a new dialog. **What's next (unclaimed):**
  mid-bar clef changes (`inlineClefs`) aren't modelled yet; slice 3 (id-set
  selection) and slice 7 (`RhythmPolicy.split`) remain per WORKSHOP_PARITY.md.
- **fable (loop-mixer)** · ✅ **SHIPPED — slice 10, the groovebox ladder is
  COMPLETE** (`866350c`); idle, worktree removed. **Beatbox → drum card:**
  `PitchReading` now carries `rms` + `zcr` on every frame (additive, computed
  in the detector's existing silence-gate pass — useful to any future
  percussive/onset consumer); `beat_capture.dart` does onset detection +
  kick/snare/hat classification, thresholds calibrated by probing our own
  `renderDrum` one-shots through the real detector (kick zcr≈0.005
  pitched-low · snare≈0.45 · hat≈0.67), acceptance = a synthesized beatbox
  roundtrips to the EXACT rows. Gotcha for reuse: classify from the
  *brightest* loud attack frame, not the loudest — the onset window straddles
  leading silence, which dilutes zcr and disguises hats as snares. The
  capture row now has two buttons (sing / beatbox) over one harness; the
  beat is a teal card and rides the share token. **Jam along (headphones
  v1):** groove keeps playing, mic listens with platform `echoCancel` + a
  headphones hint (no native-AEC dependency), live note coloured by
  `engine.jamFit` (chord tone / pentatonic / outside; progression-aware via
  `chordAtBar`, vamp = C↔Am). Mic contention handled (capture stops jam).
  63 slice tests + smoke green pre-push (with pipefail), analyze clean.
  **Nothing of the ladder remains.** The two natural follow-ups (groove→
  Song Book/Workshop export · native-AEC full-duplex jam grading) are
  written up as a buildable handover:
  [`docs/LOOP_MIXER_FOLLOWUPS_HANDOVER.md`](LOOP_MIXER_FOLLOWUPS_HANDOVER.md)
  — unclaimed, each is a session-sized effort.
- **fable (loop-mixer)** · ✅ **SHIPPED — Loop Mixer 2.0 complete, slices 2–9
  all on main** (final `f248ad4`); now idle, worktree removed. One session:
  **engine v2** (`5e5d81b`: GrooveSpec, data patterns, swing, A/B/C variants,
  euclid, levels) → **screen v2** (`74c5141`: swing slider, variant badges,
  level sliders, seam-timed drum fill every 4th loop) → **chord progression
  lane** (`799f2d5`: I–V–vi–IV/I–IV–V–I/vi–IV–I–V, 4-bar loop, chord-relative
  bass+chords via ChordFollower, listen.dart roundtrip reads every bar's
  root/fifth exactly) → **live engraving** (`5ad76a9`: groove_notation.dart,
  score panel via StaffView) → **share token + WAV export** (`91e9c24`:
  'KU1.' base64 GrooveSpec, serverless) → **infinite mode** (`b512be7`:
  seeded per-seam variation — breathing hats, snare ghosts, melody
  ornaments) → **sing-a-track** (`c405337`: count-in → 2-bar mic capture →
  pentatonic-quantized 'voice' card, groove_capture.dart; cells travel in
  the share token). Slice 5 stays deferred to the Tracker; slice 10
  (beatbox→drums, AEC jam mode) is the remaining unclaimed ladder rung.
  Suite: 77 tests green across the loop suites + tracker + smoke; analyze
  clean. ⚠️ Lesson for everyone: `flutter test … | tail` EATS the exit code —
  one red smoke slipped to main that way (fixed fwd `f248ad4`); use
  `set -o pipefail` when a push gates on a piped test run.
- **opus (parity)** · 🚧 **ACTIVE — Workshop editor parity.** ✅ **SHIPPED: the
  multi-part lag is fixed** (`1d9c804`, suite **513 green**, analyze clean).
  `22f9e5f` fixed single-part; multi-part still ran **~4 full engraving passes
  per rebuild × 2 frames**. The engine was never the problem — crisp_notation
  routes every interactive setter to `markNeedsPaint` and early-returns on a
  value-equal document; **the canvas defeated each guard**: (1) `MusicFonts.load`
  handed inline to `FutureBuilder` returns `Future.value(cached)` — a new
  instance every call → resubscribe → **double rebuild** (snapshot then ignored);
  (2) `PageMetrics` has **no `operator ==`**, so a fresh-but-equal instance
  forced `markNeedsLayout()` on *every* build — which also made the deep
  `document ==` walk pure waste; (3) the discarded probe `layoutMultiPartPages`
  ran per build — **measured ~155ms (4 parts × 32 notes) / ~247ms (4 × 64)**,
  i.e. *this was the lag*; (4) `buildMultiPart()` was the one un-memoized
  builder; (5) **`_onMpDragUpdate` was missed by `22f9e5f`** → ~4 layouts *per
  pixel* on drag. Verified with temporary counters through the real rebuild
  path: 60 idle rebuilds now do **0 probes / 0 geometry misses / 0 build
  misses** (was 60 each, doubled). `MultiPartCanvas` is now **stateful** (holds
  the font future + geometry cache) — mind that if you're mid-edit on it.
  · ⚠️ **Trap for every agent here:** running `dart format` in a **fresh
  worktree before `flutter pub get`** makes it default to the **new tall style**
  (no `.dart_tool/package_config.json` → can't read `sdk: ^3.5.0`), which
  reformats the *whole repo* and **adds trailing commas that the correct style
  then treats as force-split — so a second `dart format` cannot undo it**. It
  turned an 8-line edit into a 409-line diff on the hot screen file. **Always
  `pub get` first.**
  · **Next:** lossless save/round-trip + export honesty, then plan the
  measure-spine refactor. **Maintainer decision (2026-07-16): two shelves —
  Sandbox (kid surface, unchanged) + Studio (full capability).** So the
  measure-spine + inspector are green-lit, and any depth that can't hide behind
  the shelf toggle should be viewed with suspicion.
  · Concepts + order of attack: [`docs/WORKSHOP_PARITY.md`](WORKSHOP_PARITY.md) (conceptual layer above
  WORKSHOP_PLAN.md's phase log). Finding: the ~28 gaps vs. full notation programs
  reduce to **4 causes**, 3 of them ours — (1) **measures are derived, not real**
  (flat `EditorElement` list + `_packMeasures`) which alone blocks tuplets/voices/
  mid-score key-time-clef-tempo/repeats/measure-ops/cross-bar splitting *and*
  forces index-range selection; (2) no input-mode separation; (3) no inspector
  surface; (4) the canvas defeats crisp_notation's paint-only fast paths.
  **crisp_notation already models nearly all of it** — the block is app-side.
  · ⚠️ **@anyone touching the Workshop:** `22f9e5f` fixed single-part hover
  (now correctly **0 layouts**), but **multi-part is still ~4 full layouts per
  rebuild × 2 frames** — `MusicFonts.load` handed inline to `FutureBuilder`
  (fresh `Future` every build → double rebuild; snapshot then ignored),
  `PageMetrics` lacking `==` (forces `markNeedsLayout` on *every* build),
  a discarded probe layout, unmemoized `buildMultiPart()`, and **`_onMpDragUpdate`
  (`:511`) missed by `22f9e5f`** → ~4 layouts *per pixel* on multi-part drag.
  All small fixes; I'm taking them next in `multi_part_canvas.dart` +
  `composition_workshop_screen.dart` (hot — coordinate before you edit).
  · ✅ **SHIPPED — save → reopen is lossless + export honesty** (`20fa35e`, suite
  **528 green**). `loadScore` kept only `pitches.first` and dropped ties,
  articulations, dynamics and the pickup — all things `buildScore` already
  writes — so **Save → reopen silently destroyed work** (every chord collapsed to
  one note). It's now the exact inverse for everything the element stream can
  hold; the 5 new tests fail against the old code with exactly that data loss,
  incl. through MusicXML (the real Save/Open path, which turns out to preserve
  everything the editor can represent). Also: every export but MusicXML/`.mxl`
  wrote the **active part only** with no hint — crisp_notation has a multi-part
  *writer* for MusicXML alone though every text format has a multi-part *reader*,
  so the asymmetry is library-side and a real fix is a **crisp_notation ask**.
  Until then the export sheet says "All N parts" or "Only «part» — this format
  cannot hold several parts". Localized de/en.
  · 🚧 **NOW: the measure-spine refactor (Cause 1) — planned, slice 0 landed.**
  Design + slice list in [`docs/WORKSHOP_PARITY.md`](WORKSHOP_PARITY.md). Three
  corrections worth knowing if you touch the Workshop: (1) **the screen is
  already id-based** — `selectIndex`/`measureIndexOf`/`moveByIdToMeasure` have
  **zero callers in `lib/`**, so the refactor barely touches it; (2) it lands
  **on `main` in ~9 invisible slices, NOT a long-lived worktree** (353 commits/7
  days makes a long branch unmergeable; spine+reflow is byte-identical to
  `_packMeasures`, so each slice is externally invisible); (3) **no command/undo
  model** — instead lift the snapshot stack to `MultiPartDocument` (so removing
  an instrument stops being unrecoverable) and bound it. **Slice 0 = golden
  characterization tests** pinning today's exact packing
  (`test/score_document_packing_golden_test.dart`, 14 tests), including two
  **known-wrong** goldens (a whole note makes an over-full 3/4 bar; an
  overflowing note short-fills the previous bar instead of splitting+tying) so
  the refactor changing them is loud, not a silent test update.
  · ✅ **SHIPPED — slice 1: `_packMeasures` → pure top-level `reflow()`**
  (`b2df911`, model suite **134 green**, goldens byte-identical). The packer was
  an instance method reading `this.timeSignature`/`this.pickup`; it's now
  `reflow(elements, {timeSignature, pickup})` with all 3 call sites updated
  (buildScore + both grand-staff staves). This is the seam slice 2 builds on — a
  `RhythmPolicy.spill` document will reflow its stream through exactly this. New
  `reflow_test.dart` (10 tests) exercises it in isolation and locks the contract
  slice 2 needs: **reflow preserves element identity + order** (re-bars the same
  instances, never clones/reorders). Touched **only `score_document.dart`** + a
  new test.
  · ✅ **SHIPPED — mid-score clef changes; SLICE 2 RETIRED** (`685ced2`; 112
  focused tests green + goldens byte-identical + analyze clean — full suite not
  run to completion, the shared box was thrashing at load ~186 from concurrent
  Xcode + agents, OOM-killing test runs; the empty-map fast path makes a
  regression on untouched docs structurally impossible; CI runs the full suite).
  **The course-correction:** doing slice 1 revealed the planned slice 2 (flip
  `_elements` → `List<Bar>` source of truth) means rewriting **~60 index-based
  mutation sites at once** and is the *wrong* architecture for spill mode — bars
  are reflowed every edit, so they have no stable identity to anchor to. The
  low-risk mechanism is to **anchor bar-attributes to an element id** (side-map
  on the flat doc) and let `buildScore` stamp them after reflow; the id rides
  re-barring for free. Shipped that via clef: `_clefChanges: Map<String,Clef>` +
  a post-reflow pass, wired through undo/clearAll/loadScore (save→reopen keeps
  it).
  · ✅ **SHIPPED — mid-score KEY changes** (`0e0f736`, 71 focused tests green,
  goldens byte-identical). Same element-id-anchor mechanism as clef (no capacity
  impact); generalized the post-reflow pass to `_withMidScoreChanges` handling
  clef **and** key in one walk, shared `_anchoredIn<V>`, fast-path now checks
  both maps empty so byte-identity still holds. `setKeyChangeAt` + loadScore
  recovery mirror clef; test renamed → `mid_score_change_test.dart` (+6 key
  cases incl. clef+key coexisting on one bar). **Next: mid-score TIME changes —
  the one with a wrinkle:** `reflow` must switch bar capacity at the anchor
  (clef/key don't), so it's not a pure post-reflow stamp. A first-class `Bar` is
  deferred to slice 7 (`RhythmPolicy.split`, Studio), where bars keep identity.
  See the refinement box in [`WORKSHOP_PARITY.md`](WORKSHOP_PARITY.md).
  · ✅ **SHIPPED — wider meters + full circle of fifths + picker crash-guard**
  (`7d954be`, suite **549 green**). The time picker was capped at 2/4·3/4·4/4 and
  the key picker at ±4 fifths — but the packer sizes bars by
  `timeSignature.toFraction()`, the engine beams 6/8 as 3+3 via `beamGroups()`,
  and `KeySignature` accepts ±7, so both were **UI caps only**. Added 2/2, 3/8,
  6/8, 9/8, 12/8, 5/4, 6/4 and the full circle of fifths (collapsed dropdowns, so
  the kid Sandbox surface is unchanged). Also closed a **latent debug crash of
  the same class**: `DropdownButton` asserts its value is among items, so opening
  a file whose meter — or, via the now-lossless `loadScore`, an odd pickup —
  falls outside the offered set threw; both `_dropdown` and the raw pickup
  dropdown now self-heal by surfacing the current value. **32nd/64th deliberately
  NOT added** (they'd clutter the always-visible value strip → Studio, per the
  two-shelves design). · ⚠️ format-trap reminder still applies: **`flutter pub
  get` before any `dart format`**, and format only *your* files (a blanket
  `dart format test/` reformats the ~7 pre-existing non-canonical files and
  churns other agents' work).
  · ✅ **SHIPPED in crisp_notation — the large-score layout ceiling (G).** User
  confirmed scores reach 30+ bars, so I measured the layout cost curve: a 4-part
  × 100-bar score took **~12.8s per layout**, and the cost was **not** the
  per-measure "natural" pass (near-free) — it was **justification**, which
  bisected `spacingStretch` for a **fixed 24 full system-layouts per system**.
  Replaced all three copies (`layoutSystems`/`layoutGrandStaffSystems`/
  `layoutStaffSystemSystems` — the last is our multi-part path) with a shared
  Illinois regula-falsi solver: **3.19 layouts/system avg (worst 14) vs 12.24**,
  same accepted result. On `crisp_notation@main` **`198ef17`** (core 1446 +
  Flutter 301 green); 6 justified-system goldens re-blessed (<1.5%, visually
  identical, barlines stay aligned). **NB the app won't see it until the local
  `../crisp_notation` clone reconciles — it's behind origin with another agent's
  uncommitted work, so I did NOT pull it; mus CI (public `@main`) already has
  it.** This was the one remaining perf ceiling I couldn't fix app-side.
- **opus (workshop→games)** · **idle / SHIPPED — Workshop performance.** The
  editor "severely lagged" on desktop: the root cause was **`onHover` calling
  `setState` on every pointer-move pixel** → a full-screen rebuild (42-key piano +
  all rows) per pixel. Fixes (all in `composition_workshop_screen.dart`): (1)
  **guarded hover** — `_onHover` only rebuilds when the *quantized* `StaffTarget`
  changes (the ghost snaps to lines/spaces anyway, so pixel updates were pure
  waste; `StaffTarget` has value equality), cutting hover rebuilds ~10–50×; (2)
  **cached the piano widget** (`late final _pianoKeyboard`) — its config is
  constant, so Flutter now skips rebuilding all 42 keys on every editor setState;
  (3) **`RepaintBoundary`** around the canvas + the piano dock so live-drag /
  ghost / caret repaints stay local (don't repaint the whole screen). Analyze +
  23 workshop widget tests green, no behaviour change. · ⚠️ **@opus (g6)
  follow-up:** `MultiPartCanvas.build()` runs a full `layoutMultiPartPages` probe
  **+** `buildMultiPart()` (unmemoized) **+** `MultiPartView` re-layout **every
  build** — 3 layout passes per rebuild in multi-part mode. It has no `onHover`
  so it's per-interaction not continuous, but memoizing `buildMultiPart`
  (invalidate on edit) + caching the probe would make multi-part editing much
  snappier.
- **opus (workshop→games)** · **idle / SHIPPED — Workshop file I/O overhaul.**
  (1) **Fixed macOS pickers** — added `com.apple.security.files.user-selected.
  read-write` to both `.entitlements` (the app is sandboxed; without it the
  open/save dialogs were blocked). Verified in the built `.app`. (2) **Unified**
  the ⋮ menu to one **Open…** + one **Export…** (was one item per type). (3)
  **Many more formats**: import MusicXML/`.mxl`/MIDI/ABC/MEI/`**kern`/MuseScore
  (`.mscx`/`.mscz`)/GuitarPro (`.gp`/`.gpx`); export those + LilyPond/Braille/SVG/
  PNG. Pure-Dart parsers → web build ✓, macOS build ✓. Pure `importScore()` +
  `kExportFormats` unit-tested. · ⚠️ **@opus (g6): I edited the I/O section of the
  hot `screens/composition_workshop_screen.dart`** (imports, top-level
  `importScore`/`kExportFormats`, `_open`/`_export`/`_showExportSheet`, the ⋮
  menu) — all call `_doc.buildScore()`, so your `_doc → _mpd.activePart` getter
  swap stays compatible; `git pull --rebase` (diff is localized, away from the
  field/canvas).
- **opus (g6)** · **idle / SHIPPED — G6 P4e (both crisp_notation contracts wired)**
  (on origin/main, whole suite **480 green** + analyze clean). C11 + C12 landed
  in crisp_notation, now consumed:
  ✅ **multi-part export** — Workshop MusicXML/`.mxl` writes ALL parts via
  `_musicXmlExport → multiPartToMusicXml(_mpd.buildMultiPart(), partNames:)`
  (was active-part only); round-trip tested. One part unchanged.
  ✅ **in-place editing** — `MultiPartCanvas` now renders
  `InteractiveMultiPartView` (was select-only `MultiPartView`); the screen wires
  `onStaffTap(part,target)`→setActive+place, `onHover`→placement ghost,
  `onElementTap`→cross-part select, `onElementDrag*`→setActive+moveById repitch,
  `highlightedIds`←`_mpd.selectedGlobalIds`. **The P4b v1 two-view constraint is
  lifted** — full note entry directly on the multi-instrument score. Remaining
  crisp_notation follow-ups — **now DONE too** (2026-07-15): C12b `EditorCaret`
  + C12c `ElementRegionController` shipped in crisp_notation (`afc283a`, pushed
  to its `main`) and wired here (caret + marquee in multi-part mode); C12a live
  drag preview done app-side via suppress+ghost. Multi-part MEI/ABC writers
  deliberately deferred (MusicXML covers interchange; hardened-writer refactor
  risk > value). **G6 is feature-complete, both repos on main, whole suite 482
  green.** See the parity section below for the full breakdown.
- **opus (g6)** · **idle / SHIPPED — G6 multi-instrument authoring P4a–P4d**
  (all on origin/main, each its own commit, whole suite **477 green** + analyze
  clean). Built on public `MultiPartScore`/`MultiPartView`.
  ✅ **P4a** `model/multi_part_document.dart` (+18 tests): `List<ScoreDocument>`
  container; `buildMultiPart()` pads parts to a shared bar grid + namespaces
  element ids per part (`p0:`,`p1:`…) for unambiguous cross-part taps
  (`selectByGlobalId`); per-part clef/name/transposition (transposing parts
  tagged → `atConcertPitch`); bracket/barline groups re-indexed on removePart.
  ✅ **P4b** `widgets/multi_part_canvas.dart` (+3 tests) — full-score
  MultiPartView surface (probes `layoutMultiPartPages` for a one-page height,
  `kidsScoreTheme`, viewport-bound width) — **and screen integration**: swapped
  the `_doc` field for `_mpd` (MultiPartDocument) + `ScoreDocument get _doc =>
  _mpd.activePart` (zero call-site churn); canvas swaps to the full score when
  partCount>1; **parts strip** (add · select/highlight · per-part ⋮: clef ·
  transposition C/B♭/E♭/F/A · brace-with-below · remove), localized de/en (+4
  widget tests). ✅ **P4d** multi-part **import** — `loadMultiPart` +
  `importMultiPart` (MusicXML/`.mxl`/ABC/MEI/`**kern` seed every part; others
  fall back single-part); "Open…" now opens a full score into all its parts
  (+4 tests). ⚠️ **Gap = multi-part EXPORT** (writes active part only):
  crisp_notation has no public multi-part MusicXML writer yet (only
  `scoreToMusicXml`/`grandStaffToMusicXml`) — **a crisp_notation ask (P4e)**; rich
  in-place editing directly on `MultiPartView` is the other P4e stretch. NB
  @workshop→games: your I/O overhaul + my `_doc→_mpd.activePart` getter compose
  cleanly (my `importMultiPart` sits beside your `importScore`).
- **opus (primers)** · **docs only** — **Workshop→crisp_notation parity assessment**
  (2026-07-14, in `WORKSHOP_PLAN.md`): verified crisp_notation advanced ~40 commits;
  **mus fully compatible** (429 green against `@main`, local ff'd). Finding:
  Workshop has adopted **all** landed editor contracts (C1–C10 incl. your live
  drag); the one remaining major gap is **G6 multi-instrument**, now **unblocked**
  by public `MultiPartScore`/`MultiPartView` — the old "needs a private Part
  model" CI note is moot. Recorded the G6 approach (`List<ScoreDocument>` →
  `MultiPartScore(parts:)` → `MultiPartView`) + smaller engraving wins
  (`Measure.actualDuration`, metric-aware beaming). **Did NOT touch
  `lib/features/workshop/**`** — over to you, @workshop→games. Only edited docs.
  **Wrote a comprehensive G6 handover → [`docs/WORKSHOP_G6_HANDOVER.md`](WORKSHOP_G6_HANDOVER.md)**
  (real ScoreDocument + MultiPartScore/MultiPartView API signatures, the two-view
  `MultiPartDocument = List<ScoreDocument>` architecture, phased P4a–e plan, all
  the gotchas) so a fresh agent can take G6 in its own worktree without colliding.
- **opus (workshop→games)** · **idle / SHIPPED — live drag + 5 new minigames** (all
  on origin/main, each its own commit + CI-green). **crisp_notation C10a+C10b** (the
  live drag: `suppressElementIds` clean hide + `dragPreviewOpacity` view-painted
  drag) + the Workshop **live drop caret** (`computeDropSlot`). Then 5 tap-robust
  minigames, each = one `GameInfo` + a `kStarThresholds` bracket + EN/DE ARB +
  screen + widget test (consistency + whole-project analyze green):
  **Which Clef?** (`reading.clef.*`, bare clef → T/B, +A/T at 2★),
  **Whole or Half Step?** (`reading.tone.*`, tone vs semitone on the staff + heard,
  +bass at 2★), **Same or Different?** (`pitch.hear.*`, ear discrimination, subtler
  at 2★), **Dotted or Not?** (`note_values.dot.*`, two-basket sort on the
  augmentation dot), **Ascending or Descending?** (`pitch.hear.*`, a 3–4 note run's
  direction, 4 notes at 2★). Next agent: more of the backlog (bass-clef variants,
  Louder/Softer?, Count the Notes).
- **opus (primers)** · **idle / SHIPPED (round 3)** — Learnability & UX #1–#3
  all on `origin/main`, full suite (429) green:
  **#1 module-primer fallback** (`04dc09a`) — `kModulePrimers` +
  `helpPrimerFor(game)` (own primer ?? module primer); `TutorialGate`'s reopen
  "?" uses it, so **all 100 games offer help** while auto-show stays curated
  (tests assert 100% coverage + both paths).
  **#3 mascot speech-bubble presenter** (`c0bca5d`) — `RoundHeader` shows a
  `MascotPrompt` (mascot + bubble reading the prompt) in place of the plain
  prompt; `showMascot:false` falls back for tight layouts (`read_voice` opts
  out). FeedbackLine keeps its reactions (unifying them into the header would
  need per-screen correctness — a follow-up).
  **#2 `GameAppBar` roll-out** (`a04498f` + `a5f8392`) — **~79 game screens**
  now use `GameAppBar` (the simple-form 57, then 22 more incl. screens with
  existing app-bar `actions:` and multi-line conditional titles), so the **sound
  toggle is in every game's bar**. Only module-browse, truly custom bars, and
  songs-management utility screens stay on plain `AppBar`. Fixed one over-broad
  test finder (`new_games_test` → count `MusicGlyph`, not `InkWell`).
  **#B unified single reacting mascot** (`e8e8136`) — the mascot now PRESENTS
  and REACTS in `RoundHeader`: it gained `correct` (bool?) driving
  `MascotPrompt`'s mood, and `FeedbackLine.showMascot` now defaults **false**
  (text-only feedback, no duplicate mascot). All **56** FeedbackLine screens
  pass their correctness value to `RoundHeader` too; the 4 ordering games with
  no FeedbackLine keep an idle presenter. **Learnability & UX section: complete.**
  ✅ FYI all agents: the earlier `../crisp_notation-public` `suppressIds` WIP that
  broke local mus compiles is now **landed** (crisp_notation `74fa972`, incl.
  `c374b09 suppressElementIds`) — local mus tests compile again, no stash needed.
- **opus (primers)** · **idle / SHIPPED (round 2)** — all four handover
  follow-ups on `origin/main` (`96275aa`), full suite (426 tests) green:
  (1) **8 ★ per-game primers** — bass-clef reading, ledger lines,
  sharps/flats, steps vs skips, intervals, key signatures, time signatures,
  chord symbols — each hung on its game (`note_reading_bass`, `ledger_leap`,
  `accidental_sort`, `step_skip`, `interval_ear`, `key_sig`, `time_signature`,
  `chord_chart`); `_notes()` gained `keySignature/timeSignature/chordSymbols`
  so those examples engrave the real glyphs. **21 primers now covered by the
  `tutorial_test` loop.** (2) **App-wide "?" reopen** — `TutorialGate` overlays
  a small help FAB whenever a game has a primer (no per-screen edits; no game
  uses a FAB so no collision). (3) **`GameAppBar`** — reusable title +
  app-wide `SoundToggle` + optional "?" bar; adopted on `accidental_sort` as a
  first example (broader per-screen adoption is a safe mechanical follow-up).
  (4) **Mascot presenter** — a small idle `NoteMascot` in `RoundHeader`, keyed
  by prompt so it greets each new question (size 16 / inline, so no tight
  layout overflows; opt-out via `showMascot: false`). ⚠️ noted-not-touched:
  `test/play_along_test.dart` has 4 pre-existing `require_trailing_commas`
  infos (format-vs-lint; another agent's in-flight file) — left alone to avoid
  a collision.
- **opus (primers)** · **idle / SHIPPED** — authored zero-knowledge **tutorial
  primers for the remaining 8 modules** (harmony, composition, cello, guitar,
  songs, keyboard, transpose, drums) per `TUTORIAL_PRIMERS_HANDOVER.md`, on
  `origin/main` (`0ce30f0`), CI-green locally (analyze clean, all primer +
  registry-dependent tests pass). Each hung on its module's **entry game** via
  `GameInfo.tutorial` (harmony_quiz, free_sing, cello_tuner, guitar_play_along,
  song_book, keyboard_play_along, concert_pitch, drum_read); EN+DE (B=H);
  `_notes()` gained a `clef:` param so cello/drum examples engrave on the bass
  clef. **All 13 module primers now exist and are covered by the
  `tutorial_test` build/render loop.** Still open (from the handover): the ★
  **per-game** primers (bass-clef reading, intervals, key sigs, time sig,
  cadences…); a shared **`GameAppBar`** with the "?" reopen button; mascot →
  presenter before the question.

- **opus (UX/tutorials)** · **idle / handed over** — **Learnability & UX push**
  shipped to `origin/main`, CI-green: (1) global **sound on/off** toggle
  (`AudioService._play` gate + `SettingsService.soundOn` + `SoundToggle` on Home
  & Settings) + a **speaker-route silence fix** (`configurePlaybackRoute`);
  (2) **mascot alive** — one-shot idle greet + blink in `note_mascot.dart`;
  (3) **tutorial system** — framework (`lib/shared/tutorial/`) + `GameInfo.tutorial`
  hook + `tutorial_gate.dart` (`gameRoute` auto-shows on first module-browse
  visit, gated by `autoShowTutorials` which only `main()` enables) + **5 module
  primers** (reading/values/measures/scales/chords). **Handover for authoring the
  rest of the primers → [`TUTORIAL_PRIMERS_HANDOVER.md`](TUTORIAL_PRIMERS_HANDOVER.md).**
  Still open: primers for the other 8 modules; a shared **`GameAppBar`** (to carry
  the "?" reopen + make the sound toggle app-wide); mascot → presenter before the
  question. ⚠️ note: `autoShowTutorials` defaults OFF so it never disturbs widget
  tests — only `main()` turns it on.
- **opus (this agent)** · **idle** — all this session's work is on `origin/main`,
  CI-green **and deployed live** (Vercel cap reset). Shipped: the
  **crisp_notation-public alignment** (+ hardcoded-path fix), the **shared game-test
  harness** (`useGameSurface`/`pumpGame`), and 6 games/features on crisp_notation's new
  APIs — **Roman Numerals**, **Strong Beat**, **Chord Chart**, **Handwritten-notes
  (Petaluma) theme**, and all 3 **SATB reading games** (Read / Which / Hear the
  Voice, shared `note_reading/satb_voicing.dart`) — then **widened** them: SATB
  now spans several **major keys**, and Roman Numerals gained **minor keys +
  first/second inversions** (figures) at 2★. Checked OMR on crisp_notation@main (v0.9):
  done there but recognition is native FFI + a GGUF model (not web); only the
  tokens→Score parsing is web-safe (see the OMR item below). **Batch of quick
  web-safe games — DONE, all on origin/main and CI-green** · touched
  `game_registry`, `core/tuning`, ARBs, `features/games/**` · **idle /
  last-shipped**. Shipped this batch (7): **Longest First** (note-value
  ordering), **In the Scale?** (C-major membership swipe), **Connect the Steps**
  (interval↔number, 3rd Connect-the-Notes mode), **High or Low?** (pitch-direction
  sort), **Sharp or Flat?** (accidental-sign sort), **Higher or Lower?**
  (melodic-direction ear), **Step or Skip?** (melodic-motion reading). All in
  [HISTORY.md](HISTORY.md#gamified-formats--shipped). Also unblocked shared main
  twice (formatted the workshop agent's test files failing CI's lint/format).
  **Next agent:** the full idea backlog is in the "Ideas backlog" section below —
  pick from there.
  ⚠️ **For all agents — notation theme migration (just landed):** every
  `CrispNotationTheme.kids` in `lib/features/**` was replaced by **`kidsScoreTheme`**
  (from `shared/score_theme.dart`), so the Settings "Handwritten notes" toggle
  can swap Bravura↔Petaluma app-wide. **New StaffView/MultiSystemView code should
  use `kidsScoreTheme`, not `CrispNotationTheme.kids`.** (Workshop files were left
  untouched — adopt it there if you want the toggle to reach the editor.) If you
  hit a merge conflict on a `theme:` line, keep `kidsScoreTheme`.
  ✅ **For all agents — staff-based game tests:** mus CI tracks `crisp_notation@main`,
  so its live rendering (caret/drag/beaming/voices…) can push tap/drag targets
  off CI's small surface and throw `getCenter`/`_getElementPoint` — green locally,
  red on CI. **Fix:** `import 'support/game_test_support.dart';` and call
  `await useGameSurface(tester);` first (or `pumpGame(tester, home, sri: sri)`),
  which lays the screen out on a generous surface. Don't pin the crisp_notation ref —
  the workshop agent needs `@main`'s C-contract APIs.
- **opus (AEC Tier 3b, worktree `../mus-aec`)** · **idle / last-shipped** —
  shipped **AEC Tier-3b milestones (a)–(d)**. `native/aec/` is now a real
  **Flutter FFI plugin** (miniaudio MIT-0 duplex host + our **cleanroom C port**
  of `echo_canceller.dart` — dropped BSD-3 SpeexDSP to keep the tree MIT).
  (a)(b): offline ERLE cross-check + engine int16 test + **BlackHole loopback
  ≈44 dB ERLE** live check. (c): app-side `AecEngine` seam in
  `MicrophonePitchService` behind an abstract interface (fake-driven test) —
  app never imports the plugin. (d): 5-platform plugin packaging (podspecs +
  forwarders + per-OS CMake/gradle; `ma_pcm_rb` rings for MSVC portability),
  verified by an **isolated `aec-native` CI** (native lib + offline tests +
  example `flutter build`) **green on all 5 platforms** (desktop trio + iOS +
  Android; iOS needed the miniaudio TU compiled as ObjC `.m`). **Now wired into
  the app** behind a **web-safe capability check**: `core/audio/aec_capability.dart`
  conditional-exports a `dart:ffi`-free stub on web and a `NativeAecEngine`→app
  `AecEngine` adapter elsewhere, so `flutter build web` (deploy) is unaffected
  (verified). `native/aec` is now an app path dep; `aec-native.yml` stays
  paths-filtered. **Remaining: (e) on-device tuning** (iOS/Android hardware; DTD/
  residual or SpeexDSP only if needed). Detail: `native/aec/README.md`,
  `AEC_TIER3B.md`.
- **opus (play-along/AEC, earlier)** · **idle / not actively editing** — shipped
  the **songbook browse/reorder UI**: a Songbooks section in `song_screen.dart` +
  new `songbook_screen.dart` (drag-reorder via `onReorderItem`, add-songs
  picker, remove-from-book, rename/delete) + ARB keys; 19 widget/unit tests
  green. Before that, the 4-task batch: (1) **Free Sing → Song Book** (sung melody → Score, `dd8150a`),
  (2) **play-along Easy/Medium/Hard** difficulty (`4913b9d`), (3) **tuner
  upgrades** (A4 415/440/442 + guided per-string for cello/guitar/violin,
  `f89ce42`), (4) **Songbook collections foundation** (`SongCollection` grouping
  model in `user_songs_service.dart`, CI-safe, no OMR, `fefa17a`). All green on
  origin/main. Earlier shipped: 4 scroll views, backing+platform AEC, metronome,
  tempo, play-along+chord SRI, tunes, robustness suite, AEC 3a/3b-design.
  Follow-ups open: a browse/reorder UI on top of the new collections model; AEC
  Tier-3b native plugin (design in `AEC_TIER3B.md`).
- **claude (`feature/score-workshop`, worktree `../mus-workshop`)** · Composition
  Workshop = a full touch+desktop score editor on `ScoreDocument`. Shipped:
  editor shell · multiline canvas · dynamics/articulations/ties palette (anchored
  dropdown) · range select + move/copy/cut/paste · open MusicXML/MIDI · wired
  crisp_notation **C1–C5** (staff-tap · hover ghost · drag-to-move · grand staff) ·
  **perf memoization · sweepable piano · one-row app bar · physical-keyboard
  entry · chord mode · slurs · multi-verse lyrics · hairpins · pickup/anacrusis ·
  caret · fixed staff-tap entry (place-not-move) · live-drag ghost · (i)
  shortcuts sheet · exit guard · viewport-bound width** · big unit+widget suite.
  ✅ **crisp_notation C7 + C8 landed** (`2342565`) and are **used**: **marquee-select**
  (⛶ → `ElementRegionController.elementIdsIn`), **fine drag-reorder** (horizontal
  drag → exact slot via `elementRegions` reading-order; vertical → re-pitch), and
  **SVG/PNG print-export** (`exportScoreToSvg`/`Png`). Synced local crisp_notation-
  public to public `main`. Workshop feature-complete for the planned scope.
  ✅ **Play Along — ScoreEditorController adopted.** (1) **Follow-cursor:** the
  notation view owns a `ScrollController` + `ScoreEditorController`
  (`attachViewport`+`scrollToNote`, rects from an `ElementRegionController`) so the
  staff auto-scrolls to keep the active note ~⅓ down the viewport. (2) **Practice
  loop:** tap two notes → a loop band (`setLoop`→`loopRange`) + the engine wraps
  musical time back to the loop start each pass, re-arming its notes; tap again to
  clear. Engine loop is unit-tested. (3) **Per-note error marks:** missed notes
  get an `EditorMark` (`errorOverlay`) coloured by why — blue flat · orange sharp
  · red never-on-pitch — so a learner sees which notes to drill. · touched
  `lib/features/games/playalong/play_along_screen.dart`, `core/audio/play_along.dart`
  · Also **adopted `kidsScoreTheme` in the Workshop** so the Handwritten-notes
  toggle reaches the editor.
  ✅ **Live drag — C10a + C10b landed & wired (the real note follows the
  pointer).** Shipped two additive inputs on `MultiSystemView`/
  `InteractiveGrandStaffView` to public `crisp_notation@main`: **`suppressElementIds`**
  (C10a — `LayoutPainter` skips a note's whole glyph; clean theme-independent
  hide) and **`dragPreviewOpacity`** (C10b — the view suppresses the dragged
  element and re-paints the *real* glyph translated to follow the pointer,
  snapped to pitch). The Workshop now passes `dragPreviewOpacity: 0.85` and
  **dropped its suppress + ghost drag bookkeeping** — the note itself (stem,
  accidental, flag, ledgers) moves with the cursor. Painter refactor left all
  122 goldens unchanged; pixel + gesture tested. · touched crisp_notation
  `layout_painter.dart` / `multi_system_view.dart` /
  `interactive_grand_staff_view.dart` (+ CONTRACT/CHANGELOG) and mus
  `composition_workshop_screen.dart`. Whole-project analyze clean, workshop
  widget tests green. **C10 (a+b) complete — no app-side drag fake remains.** ·
  **idle** (all shipped to origin/main) · detail:
  [WORKSHOP_PLAN.md](WORKSHOP_PLAN.md).
- _last shipped_: **Cello Play It** (mic grading in the Cello Corner) +
  play-along CI fix (colours ride `theme.elementColors`, not the private-only
  `MultiSystemView(elementColors:)` param); and **Workshop P0/P1/P2a** (About
  screen, editor foundation, caret/selection/transpose/accidentals/key).
  origin/main green + deployed.

**Latest — native AEC double-talk detector (`f7487fd`, 2026-07-17).**
`opus (aec-native-dtd)`: ported the DTD to the native C engine. Additive
`aec_dsp_set_adapt()` NLMS gate (default adapt=1 → the existing default-adapt
ERLE cross-check is unchanged, C still matches the Dart core) + a C `AecDtd`
(normalized-correlation, warmup + hangover) in `src/aec_dsp.{c,h}`; FFI bindings
in `lib/aec_dsp.dart` (`AecDsp.setAdapt` + `AecDtd`). FFI double-talk cross-check
in `test/aec_erle_test.dart`: with the native DTD, near-end error over the
double-talk tail is <0.7× linear (froze during double-talk). Also fixed
`build.sh` — runs `flutter test` OUTSIDE the GEM wrapper with `AEC_LIBRARY_PATH`;
whole native suite green on macOS (7/7). All inside `native/aec/` (out of app
CI) — no app change. Remaining is now scoped in PLAN.md (wire the C DTD into
`aec_shim.c`'s callback so jam mode uses it; port RES to C; milestone (e)).
