// Repro for the blank staff seen on web in place-the-note: a Score whose
// measures contain whole rests, rendered with real Bravura metadata (the
// web/production path — other widget tests run without metadata).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

void main() {
  setUpAll(() {
    final metadata = File(
            '../partitura/packages/partitura/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    Bravura.debugOverrideMetadata(
      SmuflMetadata.fromJson(jsonDecode(metadata) as Map<String, Object?>),
    );
  });

  testWidgets('whole-rest measures render without exceptions',
      (tester) async {
    const wholeRest = RestElement(NoteDuration(DurationBase.whole));
    final score = Score(
      clef: Clef.treble,
      measures: [
        Measure(const [wholeRest]),
        Measure(const [wholeRest]),
        Measure(const [wholeRest]),
      ],
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: StaffView(score: score, staffSpace: 16)),
      ),
    );

    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byType(StaffView));
    expect(size.width, greaterThan(100)); // three real measures, not slivers
    expect(size.height, greaterThan(0));
  });
}
