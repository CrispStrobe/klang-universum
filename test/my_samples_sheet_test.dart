// The shared "My Samples" browser — listing, delete, and the pick/manage
// distinction (the Voice Lab picks a clip; the Sample Extractor only manages).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/features/sound_lab/my_samples_sheet.dart';
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

Float64List _tone(int n) => Float64List.fromList([
      for (var i = 0; i < n; i++) 0.4 * math.sin(2 * math.pi * 220 * i / 22050),
    ]);

MySamplesTester _sheet(WidgetTester tester) =>
    tester.state<State<MySamplesSheet>>(find.byType(MySamplesSheet))
        as MySamplesTester;

Future<void> _seed() async {
  final store = SampleClipStore();
  await store.save(
    SampleClip(
      name: 'kick',
      sampleRate: 22050,
      pcm: _tone(2205),
      source: 'kit',
    ),
  );
  await store.save(
    SampleClip(name: 'voice', sampleRate: 22050, pcm: _tone(4410)),
  );
}

/// The sheet is always shown via showModalBottomSheet in the app, which
/// provides the Material ancestor ListTile requires — mirror that here.
Widget _hosted(Widget child) => Scaffold(body: child);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('lists saved clips with their source and duration',
      (tester) async {
    await _seed();
    await pumpGame(tester, _hosted(MySamplesSheet(store: SampleClipStore())));
    await tester.pumpAndSettle();

    expect(_sheet(tester).clips.map((c) => c.name), ['kick', 'voice']);
    expect(find.text('kick'), findsOneWidget);
    expect(find.textContaining('kit'), findsOneWidget); // source shown
    expect(find.textContaining('0.10s'), findsWidgets); // 2205/22050
  });

  testWidgets('deleting a clip removes it from the store', (tester) async {
    await _seed();
    await pumpGame(tester, _hosted(MySamplesSheet(store: SampleClipStore())));
    await tester.pumpAndSettle();

    await _sheet(tester).deleteAt(0);
    await tester.pumpAndSettle();

    expect(_sheet(tester).clips.map((c) => c.name), ['voice']);
    // …and it really is gone from storage, not just the view.
    expect((await SampleClipStore().load()).map((c) => c.name), ['voice']);
  });

  testWidgets('empty library explains how to fill it', (tester) async {
    await pumpGame(tester, _hosted(MySamplesSheet(store: SampleClipStore())));
    await tester.pumpAndSettle();
    expect(_sheet(tester).clips, isEmpty);
    expect(find.textContaining('No saved samples'), findsOneWidget);
  });

  testWidgets('rows are inert when the host only manages (pickable: false)',
      (tester) async {
    await _seed();
    await pumpGame(
      tester,
      _hosted(MySamplesSheet(store: SampleClipStore(), pickable: false)),
    );
    await tester.pumpAndSettle();

    final tile = tester.widget<ListTile>(find.byType(ListTile).first);
    expect(tile.onTap, isNull);
  });

  testWidgets('rows are tappable when the host picks (pickable: true)',
      (tester) async {
    await _seed();
    await pumpGame(tester, _hosted(MySamplesSheet(store: SampleClipStore())));
    await tester.pumpAndSettle();

    final tile = tester.widget<ListTile>(find.byType(ListTile).first);
    expect(tile.onTap, isNotNull);
  });
}
