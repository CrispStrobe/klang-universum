// Major or Minor? — the triad-quality sort. Drives real drag gestures: each
// triad only drops into its correct quality basket, and sorting all four
// advances the round. Uses the shared game surface so the staff cards lay out
// on CI.

import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/chords/major_minor_sort_screen.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

Finder _cards() => find.byWidgetPredicate((w) => w is Draggable<int>);
Finder _buckets() => find.byWidgetPredicate((w) => w is DragTarget<int>);

/// Drags every card into a basket that accepts it (each triad only drops into
/// its correct quality basket, so try each in turn).
Future<void> _sortAllCards(WidgetTester tester) async {
  Future<bool> tryDrop(int bucketIndex) async {
    final before = _cards().evaluate().length;
    final end = tester.getCenter(_buckets().at(bucketIndex));
    final gesture = await tester.startGesture(tester.getCenter(_cards().first));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -30)); // cross the touch slop
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 650));
    return _cards().evaluate().length < before;
  }

  final bucketCount = _buckets().evaluate().length;
  for (var placed = 0; placed < MajorMinorSortScreen.cardCount; placed++) {
    for (var b = 0; b < bucketCount; b++) {
      if (_cards().evaluate().isEmpty || await tryDrop(b)) break;
    }
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('sorting every triad into its basket advances the round',
      (tester) async {
    final sri = SriService(getNow: () => DateTime(2026, 7, 17));
    await pumpGame(tester, const MajorMinorSortScreen(), sri: sri);

    expect(find.text('Round 1 of 6'), findsOneWidget);
    expect(_cards(), findsNWidgets(MajorMinorSortScreen.cardCount));
    expect(_buckets(), findsNWidgets(2)); // Major / Minor by default

    await _sortAllCards(tester);
    expect(_cards().evaluate().length, 0, reason: 'all cards should be placed');

    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Round 2 of 6'), findsOneWidget);

    // Correct drops score into the chord-quality skill.
    expect(sri.getDetailedBreakdown()['chords']!.keys, ['quality']);
  });

  testWidgets('at 2 stars it widens to three baskets incl. Diminished',
      (tester) async {
    final progress = ProgressService();
    await progress.load();
    progress.recordResult('major_minor_sort', score: 550, stars: 2);

    final sri = SriService(getNow: () => DateTime(2026, 7, 17));
    await pumpGame(
      tester,
      const MajorMinorSortScreen(),
      sri: sri,
      extraProviders: [
        ChangeNotifierProvider<ProgressService>.value(value: progress),
      ],
    );

    // Three baskets now, one of them Diminished (its ° glyph is in the label).
    expect(_buckets(), findsNWidgets(3));
    expect(find.textContaining('°'), findsOneWidget);

    await _sortAllCards(tester);
    expect(_cards().evaluate().length, 0, reason: 'all cards should be placed');
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Round 2 of 6'), findsOneWidget);
  });
}
