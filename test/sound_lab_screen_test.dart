// Sound Lab screen — presets, sliders, randomize all re-render the sound.

import 'package:comet_beat/features/sound_lab/sfx_engine.dart';
import 'package:comet_beat/features/sound_lab/sound_lab_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

SoundLabTester _lab(WidgetTester tester) =>
    tester.state<State<SoundLabScreen>>(find.byType(SoundLabScreen))
        as SoundLabTester;

void main() {
  testWidgets('opens with an audible sound + preset chips', (tester) async {
    await pumpGame(tester, const SoundLabScreen());
    final lab = _lab(tester);
    expect(lab.pcm, isNotEmpty);
    expect(find.text('laser'), findsOneWidget); // a preset chip
  });

  testWidgets('loading a preset changes the params and re-renders',
      (tester) async {
    await pumpGame(tester, const SoundLabScreen());
    final lab = _lab(tester);

    lab.loadPreset('laser');
    await tester.pump();
    expect(lab.params.wave, SfxWave.sawtooth); // the laser preset
    expect(lab.pcm, isNotEmpty);
  });

  testWidgets('a slider change updates the param', (tester) async {
    await pumpGame(tester, const SoundLabScreen());
    final lab = _lab(tester);

    lab.setKnob('baseFreq', 220);
    await tester.pump();
    expect(lab.params.baseFreq, 220);
  });

  testWidgets('randomize produces a different sound', (tester) async {
    await pumpGame(tester, const SoundLabScreen());
    final lab = _lab(tester);
    final before = lab.params.toJson();

    lab.randomizeSound();
    await tester.pump();
    expect(lab.params.toJson(), isNot(before));
  });
}
