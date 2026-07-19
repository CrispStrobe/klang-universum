// Creature shape mapping — pure model test.

import 'package:comet_beat/features/games/composition/loop_creatures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each track id maps to its musically-themed shape', () {
    expect(creatureShapeFor('drums'), CreatureShape.drum);
    expect(creatureShapeFor('bass'), CreatureShape.bass);
    expect(creatureShapeFor('chords'), CreatureShape.keys);
    expect(creatureShapeFor('melody'), CreatureShape.note);
    expect(creatureShapeFor('sparkle'), CreatureShape.star);
    expect(creatureShapeFor('voice'), CreatureShape.mic);
    expect(creatureShapeFor('beat'), CreatureShape.bars);
  });

  test('an unknown id falls back to a note', () {
    expect(creatureShapeFor('mystery'), CreatureShape.note);
  });
}
