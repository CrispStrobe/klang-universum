# Automatic Transcription — 3-worker handover

Full standalone prompts for THREE parallel agents building the transcription
pipeline (design: `docs/TRANSCRIPTION_SCOPING.md`; plan: `docs/PLAN.md` §
"Automatic Music Transcription"). The **seam is already in place** —
`lib/core/audio/transcription/contracts.dart` (the shared types) and
`test/transcription/note_metrics.dart` (the mir_eval-style "done" ruler,
locked). Every worker codes ONLY against those + their own module, so the three
never collide.

```
audio (Float64List mono + sampleRate)
        │
   ┌────┴─────────────────────────────┬───────────────────────────┐
   │ Worker 1 (pitch chain)           │ Worker 2 (rhythm chain)    │  Worker 3 (neural)
   │ S1 pyin.dart   → PitchTrack      │ S4 rhythm.dart             │  basic_pitch.dart (ONNX)
   │ S2 note_hmm.dart→ List<NoteEvent>│  → RhythmGrid              │   → List<NoteEvent>
   │ S3 tuning.dart                   │  + quantise → GriddedNote  │  (polyphonic)
   └────┬─────────────────────────────┴───────────┬───────────────┴──────┬─────────
        └────────────► S5 transcribe.dart (integration) ◄──────────────────┘
                       List<NoteEvent> + RhythmGrid → crisp_notation Score → MusicXML
```

---

## § Shared context (every worker: read first)

**Repo & worktree.** The app is the Flutter package `comet_beat` at
`/Users/christianstrobele/code/mus`. Rendering is a **path dependency** on
`../crisp_notation`, so your git worktree **MUST be a sibling of `mus/`** (e.g.
`../mus-transcribe-pitch`) or the path dep breaks. Create one on a feature
branch off `main`:
```bash
git -C /Users/christianstrobele/code/mus worktree add ../mus-<slug> -b feature/<slug> origin/main
```

**Build/test env (this Mac's broken-Ruby gotcha).** Wrap every flutter call:
```bash
PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT flutter test <path>
PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT flutter analyze <paths>
```
Pre-commit: **`dart format` FIRST, then `flutter analyze` LAST** ("No issues
found"). `dart fix --apply --code=<lint>` clears trailing-comma/ordering lints.

**Coordination (MANDATORY).** Update the `🚧 Actively working on` board at the
top of `docs/PLAN.md` with a claim BEFORE you start and mark it shipped after,
and `git pull --rebase origin main` then `git push origin HEAD:main` at each
checkpoint. **Commit small, merge straight to `main` — no PRs.** End commit
messages with:
`Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

**The contract (frozen).** `lib/core/audio/transcription/contracts.dart`:
```dart
typedef PitchFrame = ({double timeMs, double f0Hz, double voicedProb});
typedef PitchTrack = List<PitchFrame>;
typedef NoteEvent  = ({int midi, double onMs, double offMs, double confidence});
typedef RhythmGrid = ({double bpm, List<double> beatMs, List<double> onsetMs});
typedef GriddedNote= ({NoteEvent note, double startBeat, double beats});
```
If you truly need to change it, announce on the board first — it's the seam.

**The "done" ruler.** `test/transcription/note_metrics.dart`: `notePrf` /
`onsetPrf` (mir_eval-style P/R/F) + `notes([(midi,onMs,offMs)…])`. Your
acceptance bar is an F-number from these, not eyeballing.

**Testing = synthetic (locked) + real (CLI demo).** LOCK behaviour with
synthetic audio you control (`synth.renderSegments`/`renderWav` → PCM16 WAV →
your function). CI has no network and we do NOT bundle audio, so validate on
REAL recordings via a documented download recipe you run locally (Wikimedia
Commons, public-domain / CC0 / CC-BY — cite the licence), the same way the
shipped `recording_analysis` was: `sox`/`ffmpeg` are installed; convert
OGG→WAV mono 44.1k with `ffmpeg -i x.ogg -ac 1 -ar 44100 -c:a pcm_s16le x.wav`.
Put the expected melody/chords as a hand-labelled `notes([...])` ground truth in
your test file and report the F-measure in the commit message.

**Patent / licence (HARD).** MIT-compatible + **patent-free** only. **Clean-room
from the papers — never copy GPL code** (Tony, aubio, the Vamp plugins, Sonic
Visualiser are GPL: read the maths, write your own Dart). **AVOID** Melodia
(patented), madmom's DBN beat/downbeat trackers (Böck patents + non-commercial),
SuperFlux. **SAFE**: YIN/pYIN, CQT/HCQT, HMM/Viterbi/DTW, spectral-flux onsets,
Ellis DP beat tracker, CREPE (MIT), Basic Pitch (Apache-2.0). See
`docs/TRANSCRIPTION_SCOPING.md` § patent appendix.

**Boundaries (no collision).** Touch ONLY your listed files under
`lib/core/audio/transcription/` + `test/transcription/` (+ your board claim, +
— Worker 3 only — `pubspec.yaml`/assets for the model). Do NOT edit
`contracts.dart`, `note_metrics.dart`, another worker's module, or any hot file
(`game_registry.dart`, `tuning.dart`, ARBs, screen files).

---

## Worker 1 — pitch chain (S1 pYIN F0 + S2 note-HMM + S3 tuning)

You own the **monophonic** transcriber — the "make a sung children's song
transcribe" milestone. Read § Shared context. Worktree slug `transcribe-pitch`.

**Build, in slices, each shipped + green:**

1. **S1 · `pyin.dart` — `PitchTrack pyinF0(Float64List mono, {int sampleRate = 44100})`.**
   Clean-room **probabilistic YIN** (Mauch & Dixon 2014, on YIN 2002): the
   cumulative-mean-normalised difference function → several F0 candidates with
   probabilities per frame → a **Viterbi** pass over a pitch+voicing state
   lattice for a smooth track and a `voicedProb`. Fewer octave errors than the
   shipped MPM (`pitch_analysis.dart`). Frame hop ≈ 10 ms.

2. **S2 · `note_hmm.dart` — `List<NoteEvent> segmentNotes(PitchTrack track)`.**
   Clean-room the pYIN **note HMM** ("Tony", Mauch et al.): an HMM over
   note-pitch states with attack / stable / silent sub-states + self-transitions;
   **Viterbi** decode → note on/off/pitch. The stable state absorbs vibrato
   (±½ semitone); transitions absorb portamento. This is the piece that turns a
   sung line into notes.

3. **S3 · `tuning.dart` — `int estimateTuningCents(PitchTrack)`** + apply it so
   off-A440 recordings still snap to the right notes (F0 pitch-class histogram →
   peak offset from 12-TET). Per-note pitch = robust median over the stable
   region.

**Contract:** produce `PitchTrack` (S1) and `List<NoteEvent>` (S2) exactly as in
`contracts.dart`. Do not change the frame or note types.

**Done (measurable):**
- S1: on a rendered vibrato tone (a sine whose freq wobbles ±40 cents at 6 Hz),
  the median `f0Hz` per note is within 30 cents of truth; on the shipped
  `renderWav` C-scale, **no octave errors** across the track (all within
  ±50 cents of the played note).
- S2: on a synthetic melody (render `[60,62,64,65,67]` with simulated vibrato),
  `notePrf(groundTruth, segmentNotes(pyinF0(...)))` **F ≥ 0.9** (onsetTol 60 ms).
- Real: download "Mary Had a Little Lamb.ogg" (Wikimedia, PD), convert, and get
  **note-F ≥ 0.7** vs a hand-labelled first phrase (E D C D E E E, transposed to
  whatever key the recording is in — allow a global transpose in your metric, or
  compare the interval contour). Report the number in the commit.

**Tests:** `test/transcription/pyin_test.dart`, `note_hmm_test.dart` using
`note_metrics.dart`; real-recording validation documented in the commit (not
bundled).

**Non-collision:** only `pyin.dart` / `note_hmm.dart` / `tuning.dart` + their
tests. You also own the S5 integration + CLI once S2 lands (below), coordinating
with Worker 2 for the `RhythmGrid`.

---

## Worker 2 — rhythm chain (S4 onset + tempo + Ellis beat + quantise)

You own the **rhythm** side — independent of pitch until integration. Read
§ Shared context. Worktree slug `transcribe-rhythm`.

**Build, in slices:**

1. **`rhythm.dart` — `RhythmGrid detectRhythm(Float64List mono, {int sampleRate = 44100})`.**
   - **Onset detection**: a **spectral-flux** onset envelope (STFT magnitude,
     positive first difference summed over bins), peak-pick → `onsetMs`. Pure
     DSP, unpatented. ⚠ do NOT use SuperFlux.
   - **Tempo**: autocorrelation (or a Fourier tempogram) of the onset envelope →
     `bpm` (bias to a musical 60–180 range, resolve the octave to the strongest
     beat period).
   - **Beat tracking**: clean-room the **Ellis dynamic-programming beat tracker**
     ("Beat Tracking by Dynamic Programming", Ellis 2007 — the librosa
     `beat_track` method, ISC, patent-free): a DP that maximises onset strength +
     a tempo-consistency penalty → `beatMs`. ⚠ do NOT use madmom's DBN.

2. **`rhythm.dart` — `List<GriddedNote> quantizeToGrid(List<NoteEvent> notes, RhythmGrid grid)`.**
   Map each `NoteEvent` onset/offset onto the beat grid → `startBeat` / `beats`
   (snap to the nearest sensible subdivision — reuse ideas from the shipped
   `lib/core/audio/rhythm_quantize.dart`, which already snaps onsets to a grid).

**Contract:** consume `List<NoteEvent>`, produce `RhythmGrid` / `GriddedNote`
exactly as in `contracts.dart`. You never compute pitch.

**Done (measurable):**
- Onsets: render a click/drum pattern at a known grid (e.g. `synth` drum hits
  every 250 ms) → `onsetPrf(expectedOnsets, detectedAsNoteEvents)` **F ≥ 0.9**
  (onsetTol 30 ms). (Wrap onset ms as `NoteEvent(midi:0,onMs:x,offMs:x+1,…)` to
  reuse the metric.)
- Tempo: a 120 BPM click → `bpm` within **±3 %**; a 90 BPM one within ±3 %.
- Beat: on the 120 BPM click the `beatMs` are evenly ~500 ms apart and phase-
  aligned to the clicks.
- Quantise: synthetic notes placed exactly on beats/eighths → correct
  `startBeat`/`beats` (a quarter = 1.0, an eighth = 0.5).
- Real: download a public-domain metronome / simple drum recording (Wikimedia),
  confirm `bpm` within ±5 % of the labelled tempo; report in the commit.

**Tests:** `test/transcription/rhythm_test.dart` using synth click/drum renders
+ `note_metrics.dart`.

**Non-collision:** only `rhythm.dart` + its test. Do not touch pitch modules,
`contracts.dart`, or `rhythm_quantize.dart` (read it, don't edit it).

---

## Worker 3 — ONNX/Dart specialist: Basic Pitch (polyphonic, neural)

You are an **ONNX + Dart expert**. You own the **polyphonic** transcriber — the
only way to read real multi-instrument songs a monophonic tracker can't — by
running **Basic Pitch** on **`onnx_runtime_dart`** (already a path dep). Read
§ Shared context. Worktree slug `transcribe-basicpitch`.

### The model — Apache-2.0 ⇒ you may PORT directly (with attribution)
Basic Pitch (spotify/basic-pitch, ICASSP 2022) is **Apache-2.0 for BOTH code and
weights**. Unlike the pYIN/Tony (GPL) situation, you **may port the Python
directly** — keep the `NOTICE`/attribution — not merely clean-room. The package
ships an **ONNX** model (`nmp.onnx`) alongside TF/CoreML/TFLite.

**Constants — verify against `basic_pitch/constants.py`, do not hardcode blind:**
- 22050 Hz mono; FFT hop 256 → ~86 frames/s; ~2 s windows (`AUDIO_N_SAMPLES`)
  with an overlap the package trims (`N_OVERLAPPING_FRAMES`).
- **Front-end is IN the graph** — the shipped models take **raw audio windows**
  (shape ≈ `[1, AUDIO_N_SAMPLES]`), CQT/harmonic-stacking done internally.
  **Verify the ONNX input signature first**: if it's audio, you need **no CQT
  port**; only if it expects HCQT do you port the (patent-free) harmonic-CQT
  front-end.
- Outputs: three heads — `onset` (Yo), `note` (Yn) both 88 freqs = MIDI 21..108,
  `contour` (Yp, 3×, pitch bends). Shapes ≈ `[1, n_frames, n_freqs]`. **Inspect
  the real tensor NAMES + shapes** (via `../onnx_runtime_dart/lib/onnx_proto.dart`
  or a probe) — don't assume; watch dynamic batch/time axes.

### Contract
`Future<List<NoteEvent>> basicPitchTranscribe(Float64List mono, {int sampleRate = 44100})`
in `lib/core/audio/transcription/basic_pitch.dart`. Emit `NoteEvent` exactly per
`contracts.dart` — interchangeable with Worker 1's monophonic notes at S5.

### Pipeline
1. **Resample → 22050 mono:** `resampleLinear(mono, sampleRate / 22050)`
   (`lib/core/audio/crisp_dsp/resample.dart`; ratio = inRate/outRate, so
   44100 → `2.0`).
2. **Window** into `AUDIO_N_SAMPLES` frames with the package's overlap; pad the
   tail.
3. **Run** each window: `Tensor.float(Float32List, shape)` →
   `session.runAsync({'<inputName>': t})` → `Map<String, Tensor>`. API +
   session setup: copy the pattern in `lib/core/services/tts_service.dart` and
   `../onnx_runtime_dart/lib/onnx_runtime_dart.dart`. **onnx_runtime_dart is
   Float32** — convert Float64↔Float32 both ways.
4. **Unwrap** per-window outputs into full Yo/Yn/Yp posteriorgrams (trim overlap
   per `N_OVERLAPPING_FRAMES`).
5. **Note creation:** port basic_pitch `output_to_notes_polyphonic`
   (Apache-2.0): onset threshold (def 0.5) + frame threshold (def 0.3), form
   note segments in Yn gated by Yo, min note length (~11 frames ≈ 128 ms),
   optional pitch-bend from Yp. ⚠ the `melodia_trick` flag is a gap-fill
   heuristic *named after* Melodia — it is **NOT** the patented Melodia salience
   method; still, default it **off** for zero ambiguity.
6. **Map → NoteEvent:** `midi = 21 + freqIndex`; `onMs = startFrame * 256 / 22050
   * 1000` (≈ 11.61 ms/frame); `offMs` likewise; `confidence = note amplitude`.

### Model delivery (no bloat, CI-safe)
Download-on-demand (mirror CrispASR/Kokoro `cacheEnsureFile`); keep it **out of
the default bundle**. Confirm the Apache-2.0 `LICENSE`/`NOTICE` ships with the
file. Editing `pubspec.yaml`/`assets/` touches a shared file — **announce on the
board first**.

### Done (measurable, via `note_metrics.dart`)
- **Post-processing** (no model): a hand-built posteriorgram (synthetic Yo/Yn
  with 3 clear notes) → 3 `NoteEvent`s, deterministic. This is the core lockable
  test.
- **Synthetic end-to-end** (gated on the model present): a rendered **C-major
  triad** (C4 E4 G4, ~1 s) → 3 notes, `notePrf(gt, result).f ≥ 0.9`.
- **Real:** CC0 **"I-IV-V-I chord progression.ogg"** (Wikimedia) → recovers the
  C/F/G/C chord tones (note-F ≥ 0.6 vs a hand-labelled ground truth); runs on
  macOS via `onnx_runtime_dart`. Report the F-number in the commit.
- **CI green WITHOUT the model:** gate the model path skip-if-absent
  (`if (!modelFile.existsSync()) { markTestSkipped(...); return; }`); the
  post-processing test needs no model.

### Tests
`test/transcription/basic_pitch_test.dart`: (a) note-creation on a hand-built
posteriorgram (deterministic, no model); (b) the synthetic-triad end-to-end,
model-gated; (c) the real recording as a documented CLI demo. Score with
`note_metrics`.

**Boundaries:** only `basic_pitch.dart` + its test (+ `pubspec.yaml`/`assets/`
for the model, **announced first**). Never touch `contracts.dart`,
`note_metrics.dart`, or the pure-Dart modules.

---

## Integration (S5) — owned by Worker 1 after S2

`transcribe.dart`: `Score transcribeToScore(List<NoteEvent> notes, RhythmGrid grid)`
— combine any transcriber's `NoteEvent`s (Worker 1 OR Worker 3) with Worker 2's
`RhythmGrid`, quantise (Worker 2's `quantizeToGrid`), and emit a
`crisp_notation` `Score` (then the shipped MusicXML/MIDI export is free). Wire a
`bin/listen.dart --transcribe` flag and, optionally, an app entry via
`analyzeRecording`. Done when a real solo-instrument recording → a correct
engraved melody, note-F ≥ 0.7.
