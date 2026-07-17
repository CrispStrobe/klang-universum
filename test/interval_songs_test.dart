// The interval-mnemonic table must be musically exact: every entry's two demo
// notes have to span precisely the interval it names, in the stated direction —
// otherwise the app would teach the wrong sound for "Kuckuck" etc.

import 'package:comet_beat/core/curriculum/interval_songs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each demo spans exactly the stated interval and direction', () {
    for (final s in kIntervalSongs) {
      final expected = s.ascending ? s.semitones : -s.semitones;
      expect(
        s.demoDelta,
        expected,
        reason: '${s.song} (${s.name}) demo ${s.demo} spans ${s.demoDelta}, '
            'expected $expected',
      );
    }
  });

  test('lookup finds the cuckoo as a descending minor 3rd', () {
    final cuckoo = intervalSongFor(3, ascending: false);
    expect(cuckoo, isNotNull);
    expect(cuckoo!.song, 'Kuckuck');
    expect(
      intervalSongFor(3),
      isNull,
      reason: 'no ASCENDING minor-3rd mnemonic',
    );
  });

  test('no duplicate (size, direction) keys', () {
    final keys = kIntervalSongs.map((s) => '${s.semitones}_${s.ascending}');
    expect(keys.toSet().length, kIntervalSongs.length);
  });
}
