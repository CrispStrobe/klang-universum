// Loop Mixer — the loop-layering sandbox. Drives toggles via the
// LoopMixerTester seam (audio is a no-op in the headless test binding — the
// assertions are on the enabled set, the play state and the render).

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
}
