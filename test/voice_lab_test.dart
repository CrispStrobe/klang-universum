// Voice Lab — the transform chain (pure) + the screen driving it via an
// injected clip (no microphone).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/voice_fx.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerCell, TrackerTiming;
import 'package:comet_beat/features/sound_lab/instrument_library_store.dart';
import 'package:comet_beat/features/sound_lab/voice_lab_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

Float64List _tone(int n) => Float64List.fromList([
      for (var i = 0; i < n; i++) 0.5 * math.sin(2 * math.pi * 220 * i / 44100),
    ]);

VoiceLabTester _lab(WidgetTester tester) =>
    tester.state<State<VoiceLabScreen>>(find.byType(VoiceLabScreen))
        as VoiceLabTester;

void main() {
  group('voiceLabProcess', () {
    final clip = _tone(8820); // 0.2 s

    test('a no-op chain returns audio of the same length', () {
      final out = voiceLabProcess(clip);
      expect(out.length, clip.length);
    });

    test('speed (time-stretch) changes the length', () {
      final slower = voiceLabProcess(clip, speed: 1.5);
      expect(slower.length, greaterThan(clip.length));
      final faster = voiceLabProcess(clip, speed: 0.5);
      expect(faster.length, lessThan(clip.length));
    });

    test('a character preset changes the samples', () {
      final robot = voiceLabProcess(clip, effect: VoiceEffect.robot);
      expect(robot, isNot(clip));
    });

    test('empty clip stays empty', () {
      expect(voiceLabProcess(Float64List(0), reverb: 0.5), isEmpty);
    });

    test('tremolo is an identity at depth 0', () {
      expect(tremoloFx(clip, 0), same(clip));
    });

    test('alien (ring-mod) changes the samples when dialled in', () {
      final base = voiceLabProcess(clip);
      final wet = voiceLabProcess(clip, alien: 0.8);
      expect(wet.length, base.length);
      expect(wet, isNot(base));
    });

    test('crunch (distortion) changes the samples when dialled in', () {
      final base = voiceLabProcess(clip);
      final wet = voiceLabProcess(clip, crunch: 0.8);
      expect(wet, isNot(base));
    });

    test('echo (delay) leaves a decaying tail after the source', () {
      final wet = voiceLabProcess(clip, echo: 0.6);
      expect(wet.length, clip.length);
      // Energy past where the dry clip has decayed comes from the delay taps.
      expect(wet, isNot(voiceLabProcess(clip)));
    });
  });

  group('randomVoice (the 🎲 roll)', () {
    test('always a fun, in-range voice', () {
      for (var seed = 0; seed < 50; seed++) {
        final v = randomVoice(math.Random(seed));
        expect(v.effect, isNot(VoiceEffect.normal)); // never the plain voice
        expect(v.pitch, inInclusiveRange(-6, 6));
        expect(v.speed, inInclusiveRange(0.7, 1.5));
        for (final amt in [v.alien, v.crunch, v.tremolo, v.echo, v.reverb]) {
          expect(amt, inInclusiveRange(0.0, 1.0));
        }
        // The rendered result is non-silent for a real clip.
        final out = voiceLabProcess(
          _tone(4410),
          effect: v.effect,
          semitones: v.pitch,
          speed: v.speed,
          alien: v.alien,
          crunch: v.crunch,
          tremolo: v.tremolo,
          echo: v.echo,
          reverb: v.reverb,
        );
        expect(out, isNotEmpty);
      }
    });

    test('the same seed is reproducible; different seeds vary', () {
      expect(randomVoice(math.Random(7)), randomVoice(math.Random(7)));
      final rolls = {for (var s = 0; s < 20; s++) randomVoice(math.Random(s))};
      expect(rolls.length, greaterThan(10)); // plenty of variety
    });
  });

  testWidgets('screen processes an injected clip and reacts to controls',
      (tester) async {
    await pumpGame(tester, const VoiceLabScreen());
    final lab = _lab(tester);

    expect(lab.output, isNull); // no clip yet
    lab.debugSetClip(_tone(4410));
    await tester.pump();
    expect(lab.output, isNotEmpty);

    lab.setEffect(VoiceEffect.chipmunk);
    await tester.pump();
    expect(lab.effect, VoiceEffect.chipmunk);

    final before = lab.output!.length;
    lab.setParam('speed', 1.5);
    await tester.pump();
    expect(lab.output!.length, greaterThan(before)); // slower = longer
  });

  testWidgets('🎲 Surprise applies a random voice to the clip', (tester) async {
    await pumpGame(tester, const VoiceLabScreen());
    final lab = _lab(tester);
    lab.debugSetClip(_tone(4410));
    await tester.pump();
    final plain = lab.output;

    lab.surprise(3); // a fixed seed → deterministic in the test
    await tester.pump();
    expect(lab.effect, randomVoice(math.Random(3)).effect);
    expect(lab.output, isNot(plain)); // the voice changed
  });

  testWidgets('Save as instrument stores a reusable, playable instrument',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpGame(tester, const VoiceLabScreen(key: ValueKey('inst')));
    final lab = _lab(tester);
    lab.debugSetClip(_tone(4410));
    await tester.pump();

    await lab.saveAsInstrument('My Voice');
    await tester.pump();

    // It persisted, and rebuilds to something that actually renders a note.
    final saved = await InstrumentLibraryStore().load();
    expect(saved.map((s) => s.name), ['My Voice']);
    expect(saved.single.source, 'Voice Lab');
    final inst = saved.single.instrument;
    expect(inst, isNotNull);
    final note = inst!.renderChannel(
      const [TrackerCell(midi: 60)],
      const TrackerTiming(rows: 4),
    );
    expect(note, isNotEmpty);
  });

  testWidgets('My Samples: save the shaped voice, recall it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpGame(tester, const VoiceLabScreen(key: ValueKey('a')));
    final lab = _lab(tester);

    lab.debugSetClip(_tone(4410));
    await tester.pump();
    await lab.saveToLibrary('my voice');
    await tester.pump();
    expect(lab.library.single.name, 'my voice');

    // A distinct key forces a fresh State that loads the saved library on init.
    await pumpGame(tester, const VoiceLabScreen(key: ValueKey('b')));
    await tester.pumpAndSettle(); // let initState's async load complete
    final lab2 = _lab(tester);
    expect(lab2.library.single.name, 'my voice');
    expect(lab2.output, isNull);
    lab2.recall(0);
    await tester.pump();
    expect(lab2.output, isNotEmpty);
  });
}
