# KlangUniversum — Curriculum & Game Plan

Music notation and harmony for children from primary school onwards (6+),
decomposed into exciting minigames. EN/DE, modularly extendable, running on
iOS/Android/Web/Windows/macOS/Linux. Notation rendering via the MIT
[partitura](https://github.com/CrispStrobe/partitura) library (our own).

## Principles

1. **Minigames, not lessons.** Every skill is drilled through a game with
   rounds, scores and 1–3 stars — same loop as Space Math Academy and
   WortUniversum.
2. **SRI everywhere.** Every first-try answer feeds the SM-2 engine under
   `<module>.<skill>.<detail>`. The home-screen review button drills due
   items; the Karteikasten visualizes progress.
3. **Kid-first interaction.** partitura's kid theme (bold lines, ≥44 px hit
   targets), generous tap slop, no time pressure in level 1 of any game.
4. **Modular i18n.** All strings in ARB (EN/DE); a new module = registry
   entry + ARB keys + game screens. German conventions respected (B = H).
5. **Everything MIT** (font OFL). No LGPL anywhere — audio via
   `audioplayers`/`flutter_soloud` + permissively-licensed samples, never
   FluidSynth.

## Curriculum map

| # | Module | Skills (SRI namespace) | Games | Status |
|---|--------|------------------------|-------|--------|
| 1 | **Notenwerte** (note values & lengths) | `note_values.symbol`, `.rhythm`, `.beats` | Symbol Quiz • Duration Duel • Rhythm Echo (tap-back) • Count the Beats (dots + ties) | 4 built |
| 2 | **Noten lesen** (treble & bass clef) | `note_reading.treble`, `.bass`, `.place_*`, `.melody` | Reading Quiz ×2 • Place the Note ×2 • Melody Echo (ear↔staff) | 5 built |
| 3 | **Takte** (measures & meter) | `measures.fill`, `.meter` | Measure Filler • Meter Detective (accented downbeats by ear) | 2 built |
| 4 | **Tonleitern** (scales, Dur/Moll) | `scales.spot`, `.build`, `.hear` | Scale Detective • Scale Builder • Dur oder Moll? (ear) | 3 built |
| 5 | **Akkorde & Intervalle** | `chords.triad`, `.build`, `.interval` | Chord Quiz • Triad Builder • Interval Detective (ear) | 3 built |
| 6 | **Harmonik** (T/S/D) | `harmony.function`, `.cadence` | Function Quiz • Cadence Workshop (build T–S–D–T) | 2 built |
| 7 | **Cello-Ecke** (instrument corner) | `cello.string`, `cello.finger`, `note_reading.tenor` | Which String? (bass-clef note → C/G/D/A) • Finger Quiz (first position, 0–4) • Tenor Clef reading • *later: shifting/positions, string+finger combined ("play this note"), open-string ear tuning* | 3 built |
| 8 | **Tasten-Ecke** (piano corner) | `keyboard.find`, `.name`, `.ear`, `.melody`, `.chord` | Find the Key (staff→key, labels fade at 2★, black keys at 3★) • Key Quiz (key→name) • Echo Keys (ear→key, C anchor) • Play the Melody (sight-playing) • Chord Grip | 5 built |
| 9 | **Liederbuch** (real songs) | `songs.tune` | Song Book — public-domain children's songs as real notation with lyrics (partitura v0.4 MultiSystemView + lyrics), synth playback with a karaoke cursor, tap any note to hear it • Name That Tune (ear) • **Import**: MusicXML (paste, via partitura v0.5), ChordPro chord sheets (own parser; tappable chord chips play triads), simple monophonic MIDI (own SMF parser + sixteenth quantization; persisted as MusicXML) • *out of scope: polyphonic MIDI (transcription problem), guitar tablature (excluded from the notation library)* | 2 built + import |
| 10 | **Komponieren** | `composition.closure`, `composition.answer` | Ending Detective (does it sound finished?) • Question & Answer (antecedent/consequent) • My Melody (free-composition sandbox, no scoring) • *later: melody completion with choices, cadence-based accompaniment* | 3 built |

**Instrument corners** are the modular-extension pattern proven by the
cello module: a data table (string/finger map), instrument-specific games
reusing the shared machinery, and the right clefs (tenor for cello — the
library supports all four). A violin/viola corner is the same recipe
(violin: G/D/A/E strings, treble clef; viola: alto clef).

## Difficulty progression (within each game)

Games start at the easiest concrete slice and widen per level (driven by
stars + `kWinsRequiredForLevelUp`, tuning.dart):

- Reading/Placing: naturals on the staff → ledger lines (middle C!) →
  accidentals → mixed clefs.
- Measure Filler: 4/4 with h/q/e → 2/4, 3/4 → dotted notes → 6/8.
- Scale Detective: C/F/G major → all majors → natural minor → harmonic minor.
- Chord Quiz: major root position → minor (Dur/Moll!) → inversions →
  diminished/augmented.
- Function Quiz: C/F/G major → all keys → minor keys (with harmonic-minor
  dominant) → hear the function (audio).

## Progression (shipped)

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

## Audio (v1 shipped)

`core/audio/synth.dart` synthesizes everything in pure Dart — no assets, no
licensing: piano-ish additive tones (pitches, chords, arpeggios, sequences)
rendered to WAV and played via `audioplayers` (data-URI source on web), plus
CrispFXR-style retro square-wave SFX (correct blip, wrong buzz, fanfare —
same procedural approach as the maintainer's
[CrispFXR](https://github.com/CrispStrobe/CrispFXR-web) /
[crispaudio](https://github.com/CrispStrobe/crispaudio) projects, in Dart).
`AudioService` wires it app-wide; feedback sounds run centrally through
`QuizRoundMixin`. Shipped ear game: Major-or-Minor. Next: Rhythm Tap-Back,
Interval Detective, Meter Detective; option to graduate to `flutter_soloud`
(zlib) if latency demands it.

## Delivery

- GitHub: `CrispStrobe/klang-universum` (app), `CrispStrobe/partitura` (lib).
- Web: Vercel (`mus` project), prebuilt `build/web`, same pattern as voc.
- pub.dev publication of partitura: deliberately **not yet** (maintainer
  decision); everything is consumed via path/git.
