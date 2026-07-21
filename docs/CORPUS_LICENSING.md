# Freely-licensed music corpora — licence findings

Working notes for sourcing bundle-able ("Tier A") song/score data for CometBeat,
a COMMERCIAL children's music app shipping in **Germany**. NOT legal advice.

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
