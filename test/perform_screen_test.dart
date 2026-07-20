// Live Looper "Perform" (S1) — stack/mute/undo/redo layers + a summed mix.

import 'dart:typed_data';

import 'package:comet_beat/features/games/composition/perform_screen.dart';
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

PerformTester _perform(WidgetTester tester) =>
    tester.state<State<PerformScreen>>(find.byType(PerformScreen))
        as PerformTester;

Widget _wrap(Widget home) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('de')],
      home: home,
    );

double _peak(List<double> x) =>
    x.fold(0.0, (m, v) => v.abs() > m ? v.abs() : m);

void main() {
  testWidgets('stack layers, mute/undo/redo, and the mix reflects it',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    expect(p.layerCount, 0);
    expect(p.debugMix().every((v) => v == 0), isTrue); // silence when empty

    p.addSeed('beat');
    await tester.pump();
    p.addSeed('bass');
    await tester.pump();
    expect(p.layerCount, 2);
    expect(_peak(p.debugMix()), greaterThan(0.0)); // the jam makes sound

    // Muting a layer changes the mix; unmuting restores it.
    final full = _peak(p.debugMix());
    p.toggleMute(0);
    await tester.pump();
    expect(p.isMuted(0), isTrue);
    final muted = _peak(p.debugMix());
    expect(muted, lessThan(full)); // one layer removed → quieter/different
    p.toggleMute(0);
    await tester.pump();
    expect(p.isMuted(0), isFalse);

    // Undo drops the newest layer; redo brings it back.
    p.undoLayer();
    await tester.pump();
    expect(p.layerCount, 1);
    expect(p.canRedo, isTrue);
    p.redoLayer();
    await tester.pump();
    expect(p.layerCount, 2);

    // Clear wipes everything.
    p.clearAll();
    await tester.pump();
    expect(p.layerCount, 0);
    expect(p.canUndo, isFalse);
  });

  testWidgets('play-in a melody becomes a new layer', (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    p.startPlayIn();
    await tester.pump();
    expect(p.isPlayingIn, isTrue);

    // Tap a little C-major run.
    for (final midi in [60, 64, 67, 72]) {
      p.playInNote(midi);
    }
    p.finishPlayIn();
    await tester.pump();

    expect(p.isPlayingIn, isFalse);
    expect(p.layerCount, 1); // the played melody is now a layer
    expect(p.layerLabel(0), 'melody');
    expect(_peak(p.debugMix()), greaterThan(0.0)); // and it makes sound

    // Cancel discards without adding a layer.
    p.startPlayIn();
    p.playInNote(62);
    p.cancelPlayIn();
    await tester.pump();
    expect(p.layerCount, 1); // still just the first melody
  });

  testWidgets('play-in a beat via pads becomes a new layer', (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    p.startPlayInBeat();
    await tester.pump();
    expect(p.isPlayingIn, isTrue);

    // Tap a little kick/snare/hat pattern.
    for (final pad in ['kick', 'hat', 'snare', 'hat']) {
      p.playInPad(pad);
    }
    p.finishPlayIn();
    await tester.pump();

    expect(p.isPlayingIn, isFalse);
    expect(p.layerCount, 1);
    expect(p.layerLabel(0), 'beat');
    expect(_peak(p.debugMix()), greaterThan(0.0)); // the beat sounds

    // A melody tap while in beat mode is ignored (wrong mode).
    p.startPlayInBeat();
    p.playInNote(60); // ignored
    p.cancelPlayIn();
    await tester.pump();
    expect(p.layerCount, 1); // nothing added
  });

  testWidgets('scenes snapshot active layers; launch + arm reapply them',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    p.addSeed('beat');
    p.addSeed('bass');
    p.addSeed('chords');
    await tester.pump();
    expect(p.layerCount, 3);

    // Scene A = all three on.
    p.saveScene();
    // Scene B = just the beat (mute bass + chords, snapshot, then restore).
    p.toggleMute(1);
    p.toggleMute(2);
    p.saveScene();
    p.toggleMute(1);
    p.toggleMute(2);
    await tester.pump();

    expect(p.sceneCount, 2);
    expect(p.sceneActiveCount(0), 3);
    expect(p.sceneActiveCount(1), 1);

    // Launch scene B → only the beat is unmuted.
    p.launchScene(1);
    await tester.pump();
    expect(p.isMuted(0), isFalse);
    expect(p.isMuted(1), isTrue);
    expect(p.isMuted(2), isTrue);

    // Launch scene A → all back on.
    p.launchScene(0);
    await tester.pump();
    expect([p.isMuted(0), p.isMuted(1), p.isMuted(2)], everyElement(isFalse));

    // Arm queues without applying; launchArmed applies + clears.
    p.armScene(1);
    await tester.pump();
    expect(p.armedScene, 1);
    expect(p.isMuted(1), isFalse); // not applied yet
    p.launchArmed();
    await tester.pump();
    expect(p.armedScene, isNull);
    expect(p.isMuted(1), isTrue); // scene B applied
    expect(p.isMuted(2), isTrue);

    // Arm again toggles off.
    p.armScene(0);
    p.armScene(0);
    await tester.pump();
    expect(p.armedScene, isNull);

    // Remove a scene.
    p.removeScene(0);
    await tester.pump();
    expect(p.sceneCount, 1);
  });

  testWidgets('bounce builds My-Samples clips (whole mix + per active layer)',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    p.addSeed('beat');
    p.addSeed('bass');
    await tester.pump();

    // Whole loop → one clip that carries sound.
    final mix = p.debugBounce('Perf');
    expect(mix.length, 1);
    expect(mix.first, isA<SampleClip>());
    expect(mix.first.name, 'Perf');
    expect(mix.first.pcm.isNotEmpty, isTrue);
    expect(_peak(mix.first.pcm.toList()), greaterThan(0.0));

    // Per layer → one clip per ACTIVE layer.
    expect(p.debugBounce('Perf', perLayer: true).length, 2);

    // Muting a layer drops it from the per-layer bounce.
    p.toggleMute(0);
    await tester.pump();
    expect(p.debugBounce('Perf', perLayer: true).length, 1);

    // Nothing playing → nothing to bounce.
    p.clearAll();
    await tester.pump();
    expect(p.debugBounce('Perf'), isEmpty);
    expect(p.debugBounce('Perf', perLayer: true), isEmpty);
  });

  testWidgets('sample voice plays pitched + records a melody in that sound',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    final sample = Float64List(4410)..fillRange(0, 4410, 0.5);
    p.setSampleVoice(sample, baseMidi: 60, name: 'meow');
    await tester.pump();
    expect(p.hasSampleVoice, isTrue);
    expect(p.voiceName, 'meow');

    // Pitch: at the base note = original length; an octave up = half as long.
    expect(p.debugPitched(60).length, 4410);
    final octaveUp = p.debugPitched(72);
    expect(octaveUp.length, 2205);
    expect(_peak(octaveUp.toList()), greaterThan(0.0));

    // Recording a melody now uses the sample → a non-silent 'melody' layer.
    p.startPlayIn();
    for (final m in [60, 64, 67]) {
      p.playInNote(m);
    }
    p.finishPlayIn();
    await tester.pump();
    expect(p.layerCount, 1);
    expect(p.layerLabel(0), 'melody');
    expect(_peak(p.debugMix().toList()), greaterThan(0.0));

    // Clearing the voice returns to the synth.
    p.clearSampleVoice();
    await tester.pump();
    expect(p.hasSampleVoice, isFalse);
    expect(p.debugPitched(60), isEmpty);
  });

  testWidgets('play/stop toggles and does not crash without audio',
      (tester) async {
    await tester.pumpWidget(_wrap(const PerformScreen()));
    await tester.pump();
    final p = _perform(tester);

    p.play(); // no layers yet → stays stopped
    expect(p.isPlaying, isFalse);

    p.addSeed('melody');
    await tester.pump();
    p.play();
    expect(p.isPlaying, isTrue);
    p.stop();
    expect(p.isPlaying, isFalse);
  });
}
