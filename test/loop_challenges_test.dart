// Loop Mixer §E-2 — band challenges: pure predicates over the enabled set.
import 'package:comet_beat/features/games/composition/loop_challenges.dart';
import 'package:flutter_test/flutter_test.dart';

BandChallenge _byId(String id) => kBandChallenges.firstWhere((c) => c.id == id);

void main() {
  test('challenge ids are unique and stable', () {
    final ids = kBandChallenges.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids, containsAll(['sparkle', 'bass', 'melody', 'layers']));
  });

  test('each predicate detects the state it asks for', () {
    expect(_byId('sparkle').check({'sparkle'}), isTrue);
    expect(_byId('sparkle').check({'drums'}), isFalse);

    expect(_byId('bass').check({'bass'}), isTrue);
    expect(_byId('bass').check({'melody'}), isFalse);

    // "add a tune" accepts either a melody or chords.
    expect(_byId('melody').check({'chords'}), isTrue);
    expect(_byId('melody').check({'melody'}), isTrue);
    expect(_byId('melody').check({'drums'}), isFalse);

    expect(_byId('layers').check({'drums', 'bass', 'melody'}), isTrue);
    expect(_byId('layers').check({'drums', 'bass'}), isFalse);

    expect(_byId('fullBand').check({'drums', 'bass', 'melody'}), isTrue);
    expect(_byId('fullBand').check({'drums', 'bass'}), isFalse);
  });
}
