# Freely-licensed music corpora — licence findings

Working notes for sourcing bundle-able ("Tier A") song/score data for CometBeat,
a COMMERCIAL children's music app shipping in **Germany**. NOT legal advice.

---

# SCOPING (2026-07-21) — sources × our import reach

Scoped against what we can actually ingest. Three findings reframe the hunt:

**A. We import almost every symbolic format — so "reachable" is rarely the
constraint; LICENCE is.** App import filters (verified in code):

| Format | ext | into |
|---|---|---|
| MusicXML (+zip) | musicxml / xml / mxl | full Score |
| MIDI | mid / midi | full Score |
| ABC | abc | full Score |
| MEI | mei | full Score |
| **Humdrum kern** | krn | full Score (rare in consumer apps — our edge) |
| MuseScore | mscx / mscz | full Score |
| Guitar Pro (GPIF) | gp / gpx | full Score + **tab** |
| ChordPro | cho / pro | chord sheet |
| JAMS | jams | chords + melody |
| ASCII tab | (text) | tab Score |

In-library but **not yet wired to the UI**: `scoreFromSemantic` (PrIMuS-style
"semantic" encoding) and `scoreFromLilyNotes`. These are the cheapest new
"filters" — the parser already exists, only UI wiring is missing.

**B. TABS: don't source them — generate them.** Every large Guitar-Pro corpus is
a scrape of in-copyright songs. DadaGP (the biggest, ~26k) is **research-access-
only** and sourced from Ultimate Guitar — both axes dirty. BUT we already own
`arrangeTab` + `gpFretPlanFor` + `scoreToGpif` + the `tabconv` CLI, i.e. we
**manufacture playable tab from any score**. So the tab corpus == the clean score
corpus, run through our own arranger. Zero third-party tab licensing needed.

**C. The academic classical corpora are a NonCommercial trap.** Verified verbatim
across 6 repos: craigsapp **bach-370-chorales**, **mozart-piano-sonatas**,
**joplin**, and DCMLab **ABC**, **mozart_piano_sonatas**, **beethoven_piano_
sonatas** are all **CC BY-NC-SA 4.0**. Axis-2 clean (all long-dead composers),
axis-1 FAIL for a commercial app. Reachable (kern/ABC/MuseScore) but dev/test
only. The "obvious" symbolic-classical route is closed for shipping.

## Ranked shippable candidates (both axes, format-reachable)

1. **OpenScore Lieder** — **CC0** (verbatim confirmed), 1,200+ 19th-c. art songs,
   MusicXML → already reachable. Multi-part + lyrics. Axis-2: 19th-c. composers +
   poets; run the OpenEWLD composer-AND-poet death-date filter (a sampled 8 poets
   all pre-1948). **Top pick: biggest clean, real-repertoire growth, no new code.**
2. **PDMX is_original slice** — **CC0**, 7,549 files clean on both axes (quantified
   offline: cc-zero ∧ no-conflict ∧ is_original). Original amateur compositions,
   MusicXML. Self-attested originality → wants a dup/plagiarism pass.
3. **OpenScore String Quartets** — CC0 (same project), MusicXML. Chamber, PD
   composers. Smaller; same clean profile.
4. **Mutopia** — no NC files found; per-piece PD / CC BY / CC BY-SA mix (BY-SA =
   copyleft on a bundle). Native `.ly` (a new filter) or the generated MIDI
   (reachable now). Needs per-piece licence + modern-editor-rights filter.
5. **GregoBase** — CC0 Gregorian chant. Niche for kids; needs a GABC→model
   converter (or its MusicXML export). 100% clean.

## Cheapest "add a filter" unlocks (the user's hint)

- **Wire `scoreFromSemantic` to the import UI → PrIMuS** (~87k real music
  incipits). Parser already exists; only UI + a format probe needed. ⚠ LICENCE
  UNVERIFIED — PrIMuS is RISM-derived; confirm CC BY/CC0 before relying on it.
- **EsAC → kern/model converter → Essen Folksong Collection** (~20k European folk
  melodies, incl. German — high pedagogical fit). ⚠ Essen licence was flagged
  uncertain earlier; and folk = modern-arrangement (§3) risk. Verify first.
- **`.ly` importer → Mutopia native** (bigger lift; MIDI path already works, so
  low priority).

## Verified-rejected this scoping pass

- **DadaGP** and all Guitar-Pro tab archives — research-only / UG scrapes of
  in-copyright songs. (Generate tabs instead — finding B.)
- **craigsapp kern + DCML corpora** — CC BY-NC-SA (finding C). Dev/test only.

## Still to verify (have web budget; agents were rate-limited, direct fetch works)

PrIMuS licence · Essen/EsAC licence · Mutopia per-piece breakdown · RISM/MEI
incipit corpora (possible MEI unlock) · OpenScore Lieder full composer+poet
death-date sweep.

---

## The test every candidate must pass — TWO axes

A dataset qualifies for shipping only if BOTH are clean:

- **Axis 1 — the encoding/transcription licence** (CC0 / CC BY / MIT = ok;
  CC BY-NC / unstated = not).
- **Axis 2 — the underlying work.** EU term is **life+70**, and for co-written
  works it runs from the **last surviving** author. The app ships in Germany, so
  **US-only public domain ("published before 1929/1931") is NOT sufficient.**

A CC0 transcription of an in-copyright song fails axis 2. This is the trap that
sank most candidates below.

## Status of this sweep

A large parallel research sweep was **cut short by the weekly API limit**
(resets 2026-07-25). The VPS holding the corpus + `LICENSES.md` was also
unreachable. So this file records what was VERIFIED before the cutoff and marks
everything else as unconfirmed. Re-run after 07-25 with the VPS back.

## Already shipped-clean (verified earlier this effort, on the VPS)

| Dataset | Files | Axis 1 | Axis 2 |
|---|---|---|---|
| GuitarSet | 360 jams | CC BY 4.0 (Zenodo API) | original recordings — nothing underneath ✅ |
| Harmonix | 912 jams | MIT | beat/segment timestamps only ✅ |
| jams-pkg | 7 jams | ISC | synthetic ✅ |
| OpenEWLD-eu-pd | 87 works / 103 mxl | MIT | author-death-date filtered to EU-PD ✅ (defensible, not "cleared") |

## VERIFIED this sweep — promising

- **OpenScore Lieder** and **OpenScore String Quartets** (MuseScore/OpenScore):
  **axis 1 = CC0** on the engravings (verified). Axis 2 = art song / quartets by
  long-dead composers, BUT each song pairs a composer AND a poet, and BOTH must
  be pre-1956 deaths. A death-year check on 8 sampled Lieder poets came back all
  pre-1948 (Campbell d.1914, Coleridge 1907, Crewe-Milnes 1945, Davidson 1909,
  Evers 1947, Eschelbach 1948, Falke 1916, Fallström 1937) — encouraging but a
  sample. **Next action:** apply the same Wikidata death-date filter used for
  OpenEWLD (composer AND poet) to the full Lieder corpus. This is the strongest
  lead for growing Tier A: CC0 + filterable + real multi-part scores with lyrics.
- **PDMX** (Public Domain MusicXML, from MuseScore) — 254,077 scores, analysed
  **offline from its metadata CSV**. The headline "public domain" is mostly the
  **PD Mark** (210,364) — a *claim*, not a grant, and not a licence. Only 43,713
  are real **CC0** waivers; 33,142 of those carry no `license_conflict`. BUT the
  CC0 waiver is on the ENGRAVING only — the clean-CC0 set still contains
  "Seven Nation Army", "Crimson Peak - Edith's Theme", "Light of the Seven",
  i.e. in-copyright songs whose uploader waived rights they didn't hold (axis-2
  fail). The **`is_original` flag** (uploader's own composition) is the axis-2
  filter: **CC0 + no-conflict + is_original = 7,549 files** that are clean on
  BOTH axes. Caveat: `is_original` is self-attestation, so this is "defensible",
  not "cleared" — worth a plagiarism/duplicate pass before shipping. Still, 7.5k
  original CC0 scores is the single biggest verified Tier-A candidate found.
- **GregoBase** — Gregorian chant, **CC0** (verified fragment). Axis 2 trivially
  clear (medieval plainchant). Niche for a kids' app but 100% clean.
- **Mutopia** — a scan found **zero non-commercial files**; licences are a mix of
  PD / CC BY / CC BY-SA. CC BY-SA imposes copyleft on a bundle — usable but a
  real obligation. Per-piece licence + modern-editor rights still need a filter.

## VERIFIED this sweep — REJECTED

- **thesession.org** (and everything downstream: **folk-rnn**, folk-rnn-webapp,
  themachinefolksession): the data dump is **ODbL + an explicit anti-LLM clause**
  (added 2025-10, tightened 2026-06). folk-rnn's MIT covers **code only**; it
  scraped thesession ~2015 when the dump had **no licence at all**. ODbL on a
  bundled corpus triggers share-alike (§4.4) + machine-readable source offer
  (§4.6) + attribution (§4.3), and §2.4 disclaims rights in the individual
  transcriptions — which, per thesession's own discussion, vest in each
  **transcriber**. Reject for a commercial bundle.
- **German folk-song sites** — volksliederarchiv.de (private/non-commercial only,
  notation walled off in robots.txt), lieder-archiv.de (asserts copyright on its
  Notensätze; commercial use, DB ingestion and republication all forbidden — but
  offers a PAID licence route), liederlexikon.de (all-rights-reserved, NOT CC,
  named living engraver + in-copyright 20th-c. works), ZPKM Freiburg (catalogues
  only, no downloadable corpus). All four: reject as-is.

## The recurring German-law point (from multiple sources, incl. the sites themselves)

Even for a PD tune, a **modern Notensatz / arrangement carries its own fresh
copyright** (§3 UrhG), and a curated collection carries a **database right**
(§4 / §87a-e UrhG). "gemeinfrei"/"GEMA-frei" ≠ "free to bundle". Lyrics clear
**separately** from melody and often later.

## Recommended next actions (when limits + VPS return)

1. **OpenScore Lieder, death-date filtered** — reuse the OpenEWLD filter on both
   composer and poet. Highest-value clean growth for Tier A.
2. **Self-engrave German Kinderlieder** from pre-1900 PD facsimiles (Erk/Böhme
   *Deutscher Liederhort*, Zuccalmaglio) into our own MusicXML via the existing
   crisp_notation pipeline — sidesteps every third-party encoding/DB claim.
3. Anything commercial-critical: a Fachanwalt für Urheberrecht sign-off, given
   the §3/§4 exposure and the axis-2 questions.
