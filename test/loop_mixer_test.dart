// Loop Mixer — the loop-layering sandbox. Drives toggles via the
// LoopMixerTester seam (audio is a no-op in the headless test binding — the
// assertions are on the enabled set, the play state and the render).

import 'package:crisp_notation/crisp_notation.dart' show StaffView;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/features/games/composition/loop_mixer_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

LoopMixerTester _game(WidgetTester tester) =>
    tester.state<State<LoopMixerScreen>>(find.byType(LoopMixerScreen))
        as LoopMixerTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('toggling cards layers tracks and starts/stops the groove',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);

    expect(game.enabledTracks, isEmpty);
    expect(game.isPlaying, isFalse);

    game.toggleTrack('drums');
    await tester.pump();
    expect(game.enabledTracks, {'drums'});
    expect(game.isPlaying, isTrue);

    game.toggleTrack('bass');
    await tester.pump();
    expect(game.enabledTracks, {'drums', 'bass'});
    expect(game.isPlaying, isTrue);

    // Untoggling the last card stops the groove.
    game.toggleTrack('drums');
    game.toggleTrack('bass');
    await tester.pump();
    expect(game.enabledTracks, isEmpty);
    expect(game.isPlaying, isFalse);
  });

  testWidgets('cards are tappable and Stop clears the whole band',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);

    await tester.tap(find.text('Drums'));
    await tester.tap(find.text('Melody'));
    await tester.pump();
    expect(game.enabledTracks, {'drums', 'melody'});

    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(game.enabledTracks, isEmpty);
    expect(game.isPlaying, isFalse);
  });

  testWidgets('tempo chips retune the groove', (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    expect(game.tempoBpm, 100);

    game.toggleTrack('chords');
    await tester.pump();

    await tester.tap(find.text('Fast'));
    await tester.pump();
    expect(game.tempoBpm, 120);
    expect(game.isPlaying, isTrue, reason: 'groove restarts at the new tempo');
  });

  testWidgets('variant badge, level slider and swing drive the engine',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);

    game.toggleTrack('drums');
    await tester.pump();
    expect(game.variantOf('drums'), 0);

    // The A badge on the drums card cycles the pattern variant.
    await tester.tap(find.text('A').first);
    await tester.pump();
    expect(game.variantOf('drums'), 1);
    expect(find.text('B'), findsOneWidget);

    game.setTrackLevel('drums', 0.4);
    game.setSwing(0.3);
    await tester.pump();
    expect(game.levelOf('drums'), closeTo(0.4, 1e-9));
    expect(game.swing, closeTo(0.3, 1e-9));
    expect(game.isPlaying, isTrue);
  });

  testWidgets('harmony chips switch between the vamp and a progression',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    expect(game.progressionId, isNull);

    game.toggleTrack('bass');
    await tester.pump();

    await tester.tap(find.text('I–V–vi–IV'));
    await tester.pump();
    expect(game.progressionId, 'axis');
    expect(game.isPlaying, isTrue, reason: 'groove restarts on the song loop');

    await tester.tap(find.text('Free'));
    await tester.pump();
    expect(game.progressionId, isNull);
  });

  testWidgets('the score panel engraves the leading enabled track',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);
    expect(game.scoreVisible, isFalse);

    game.toggleTrack('melody');
    await tester.pump();
    game.toggleScorePanel();
    await tester.pump();
    expect(game.scoreVisible, isTrue);
    expect(find.byType(StaffView), findsOneWidget);

    // No pitched track enabled → the panel collapses gracefully.
    game.toggleTrack('melody');
    await tester.pump();
    expect(find.byType(StaffView), findsNothing);
  });

  testWidgets('a groove code captures and restores the whole state',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);

    game.toggleTrack('drums');
    game.toggleTrack('melody');
    game.setSwing(0.2);
    game.setProgression('ballad');
    await tester.pump();
    final token = game.grooveToken;

    // Wipe everything, then load the code back.
    game.stopAll();
    game.setSwing(0);
    game.setProgression(null);
    await tester.pump();
    expect(game.enabledTracks, isEmpty);

    expect(game.loadGrooveToken(token), isTrue);
    await tester.pump();
    expect(game.enabledTracks, {'drums', 'melody'});
    expect(game.swing, closeTo(0.2, 1e-9));
    expect(game.progressionId, 'ballad');
    expect(game.isPlaying, isTrue, reason: 'a loaded groove starts playing');

    expect(game.loadGrooveToken('garbage'), isFalse);
  });

  testWidgets('every 4th loop schedules the drum fill at the seam',
      (tester) async {
    await pumpGame(tester, const LoopMixerScreen());
    final game = _game(tester);

    game.toggleTrack('drums');
    await tester.pump();
    expect(game.loopIteration, 0);

    // Wraps 1–2 keep the groove; the wrap into iteration 3 (the 4th loop)
    // swaps in the fill, the next wrap swaps back — none may throw with the
    // headless audio stub.
    for (var wrap = 1; wrap <= 5; wrap++) {
      game.debugLoopWrap();
      await tester.pump();
      expect(game.loopIteration, wrap);
    }
  });
}
