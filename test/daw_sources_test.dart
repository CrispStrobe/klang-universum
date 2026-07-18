// Per-module ClipSource adapters: a DrumKit beat and a Loop Mixer groove as DAW
// clips. Rendered by the real module renderers, then placed on a timeline. Pure,
// headless.

import 'package:comet_beat/core/audio/daw_sources.dart';
import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:crisp_notation/crisp_notation.dart'
    show
        Clef,
        DurationBase,
        Measure,
        NoteDuration,
        NoteElement,
        Pitch,
        RestElement,
        Score,
        Step;
import 'package:flutter_test/flutter_test.dart';

const _quarter = NoteDuration(DurationBase.quarter);

DrumRowsPattern _beat(Map<Drum, String> rows) {
  final map = {
    for (final d in Drum.values) d: List<bool>.filled(kPatternSteps, false),
  };
  rows.forEach((drum, s) {
    for (var i = 0; i < s.length && i < kPatternSteps; i++) {
      map[drum]![i] = s[i] == 'x';
    }
  });
  return DrumRowsPattern(map);
}

bool _silent(Iterable<double> pcm) => pcm.every((s) => s == 0);

void main() {
  group('DrumSource', () {
    const timing = LoopTiming(tempoBpm: 100);

    test('renders the beat to real (non-silent) audio', () {
      final src =
          DrumSource(_beat(const {Drum.kick: 'x...x...x...x...'}), timing);
      final pcm = src.render(kDawSampleRate);
      expect(pcm, isNotEmpty);
      expect(_silent(pcm), isFalse);
      expect(pcm.length, timing.totalSamples);
    });

    test(
        'cacheKey is equal for equal beats, differs when the beat or timing '
        'changes', () {
      final a = DrumSource(_beat(const {Drum.kick: 'x.......'}), timing);
      final b = DrumSource(_beat(const {Drum.kick: 'x.......'}), timing);
      final c = DrumSource(_beat(const {Drum.snare: 'x.......'}), timing);
      final d = DrumSource(
        _beat(const {Drum.kick: 'x.......'}),
        const LoopTiming(tempoBpm: 120),
      );
      expect(a.cacheKey, b.cacheKey); // same beat + timing
      expect(a.cacheKey, isNot(c.cacheKey)); // different drum
      expect(a.cacheKey, isNot(d.cacheKey)); // different tempo
    });

    test('a beat clip renders onto a DAW timeline at its placement', () {
      final src = DrumSource(_beat(const {Drum.kick: 'x...x...'}), timing);
      final timeline = DawTimeline(
        tracks: [
          DawTrack(clips: [Clip(source: src, startMs: 500)]),
        ],
      );
      final mix = renderTimeline(timeline);
      // Placed 500 ms in, so the first half-second is silence, then audio.
      const startSample = 500 * kDawSampleRate ~/ 1000;
      expect(_silent(mix.sublist(0, startSample)), isTrue);
      expect(_silent(mix.sublist(startSample)), isFalse);
    });
  });

  group('GrooveSource', () {
    test('cacheKey follows the spec identity', () {
      const spec = GrooveSpec(enabled: {'drums'});
      expect(GrooveSource(spec).cacheKey, 'groove:${spec.cacheKey}');
      const other = GrooveSpec(enabled: {'drums'}, tempoBpm: 120);
      expect(GrooveSource(spec).cacheKey, isNot(GrooveSource(other).cacheKey));
    });

    test('renders a groove to real (non-silent) audio', () {
      const spec = GrooveSpec(enabled: {'drums'});
      final pcm = GrooveSource(spec).render(kDawSampleRate);
      expect(pcm, isNotEmpty);
      expect(_silent(pcm), isFalse);
    });
  });

  group('ScoreSource', () {
    // A note, a rest, then a C-major chord — one quarter each.
    Score melody() => Score(
          clef: Clef.treble,
          measures: [
            Measure([
              NoteElement.note(const Pitch(Step.c), _quarter),
              const RestElement(_quarter),
              const NoteElement(
                pitches: [Pitch(Step.c), Pitch(Step.e), Pitch(Step.g)],
                duration: _quarter,
              ),
            ]),
          ],
        );

    test('renders notes as sound, rests as silence, chords included', () {
      final pcm = renderScore(melody());
      const q = kDawSampleRate ~/ 2; // a 500 ms quarter at 44.1k
      expect(pcm.length, 3 * q);
      expect(_silent(pcm.sublist(0, q)), isFalse); // the C note
      expect(_silent(pcm.sublist(q, 2 * q)), isTrue); // the rest
      expect(_silent(pcm.sublist(2 * q, 3 * q)), isFalse); // the chord
    });

    test('cacheKey is equal for equal scores, differs on the notes', () {
      expect(
        ScoreSource.single(melody()).cacheKey,
        ScoreSource.single(melody()).cacheKey,
      );
      final other = Score(
        clef: Clef.treble,
        measures: [
          Measure([NoteElement.note(const Pitch(Step.d), _quarter)]),
        ],
      );
      expect(
        ScoreSource.single(melody()).cacheKey,
        isNot(ScoreSource.single(other).cacheKey),
      );
    });

    test('a score clip renders onto a DAW timeline', () {
      final t = DawTimeline(
        tracks: [
          DawTrack(clips: [Clip(source: ScoreSource.single(melody()))]),
        ],
      );
      final mix = renderTimeline(t);
      expect(mix, isNotEmpty);
      expect(_silent(mix), isFalse);
    });
  });
}
