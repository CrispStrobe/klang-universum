// Tracker (Sandbox skin) — drives the grid via the TrackerTester seam (audio is
// a no-op in the headless binding — the assertions are on the placed notes, the
// play state and the selected channel).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/features/games/composition/tracker_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

TrackerTester _game(WidgetTester tester) =>
    tester.state<State<TrackerScreen>>(find.byType(TrackerScreen))
        as TrackerTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('placing a note starts the groove; clearing stops it',
      (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);

    expect(game.noteCount, 0);
    expect(game.isPlaying, isFalse);

    game.tapCell(0, 0);
    await tester.pump();
    expect(game.noteCount, 1);
    expect(game.isPlaying, isTrue);

    game.clearAll();
    await tester.pump();
    expect(game.noteCount, 0);
    expect(game.isPlaying, isFalse);
  });

  testWidgets('tapping the same cell twice toggles the note off',
      (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);

    game.tapCell(2, 3);
    await tester.pump();
    expect(game.noteCount, 1);

    game.tapCell(2, 3);
    await tester.pump();
    expect(game.noteCount, 0);
  });

  testWidgets('each instrument tab edits its own channel', (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);
    expect(game.channelIds.length, greaterThanOrEqualTo(2));
    expect(game.selectedChannel, 0);

    game.tapCell(0, 0); // channel 0
    game.selectChannel(1);
    await tester.pump();
    expect(game.selectedChannel, 1);

    game.tapCell(1, 1); // channel 1
    await tester.pump();
    // Two notes total, one per channel — switching tabs didn't move a note.
    expect(game.noteCount, 2);
  });

  testWidgets('the Clear button empties the pattern', (tester) async {
    await pumpGame(tester, const TrackerScreen());
    final game = _game(tester);

    game.tapCell(0, 0);
    game.tapCell(1, 2);
    await tester.pump();
    expect(game.noteCount, 2);

    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(game.noteCount, 0);
    expect(game.isPlaying, isFalse);
  });
}
