// PianoKeyboard — the shared tappable keyboard. Covers the new per-key hint
// captions (D1c: the Tracker's computer-key letters shown ON the keys).

import 'package:comet_beat/shared/widgets/piano_keyboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders a computer-key hint on the mapped keys', (tester) async {
    var tapped = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 80,
            width: 700,
            child: PianoKeyboard(
              whiteKeyCount: 7, // one octave
              keyHints: const {60: 'Z', 61: 'S', 62: 'X'}, // C, C#, D
              onKeyTap: (m) => tapped = m,
            ),
          ),
        ),
      ),
    );

    // Hints appear on both a white key (Z on C) and a black key (S on C#).
    expect(find.text('Z'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);
    expect(find.text('X'), findsOneWidget);
    // A key with no hint shows nothing extra.
    expect(find.text('Q'), findsNothing);

    // The keys are still tappable.
    await tester.tap(find.text('Z'));
    expect(tapped, 60);
  });

  testWidgets('no hints by default', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 80,
            width: 700,
            child: PianoKeyboard(whiteKeyCount: 7),
          ),
        ),
      ),
    );
    expect(find.text('Z'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
