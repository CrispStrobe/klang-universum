// BeatBridge — the shared groove backbone. A published SharedBeat is a copy
// (source edits don't leak), fits to any grid length, and reads back via the
// process-wide bridge. Pure Dart.

import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/core/services/beat_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(BeatBridge.instance.clear);

  test('SharedBeat copies rows so later source edits do not leak', () {
    final src = {
      Drum.kick: [true, false, true, false],
      Drum.snare: [false, true, false, true],
    };
    final beat = SharedBeat(rows: src, tempoBpm: 100);
    src[Drum.kick]![1] = true; // mutate the ORIGINAL after sharing
    expect(beat.rows[Drum.kick], [true, false, true, false]);
    expect(beat.steps, 4);
    expect(beat.isEmpty, isFalse);
  });

  test('rowsFitted pads/truncates and includes every drum', () {
    final beat = SharedBeat(
      rows: {
        Drum.kick: [true, true], // shorter than target
        Drum.snare: [true, false, true, false, true, true], // longer
      },
      tempoBpm: 120,
    );
    final fitted = beat.rowsFitted(4);
    expect(fitted.length, Drum.values.length); // every drum present
    expect(fitted[Drum.kick], [true, true, false, false]); // padded
    expect(fitted[Drum.snare], [true, false, true, false]); // truncated
    expect(fitted[Drum.crash], [false, false, false, false]); // absent → silent
  });

  test('an all-silent beat is empty; hasBeat reflects it', () {
    expect(BeatBridge.instance.hasBeat, isFalse);
    final silent = {
      Drum.kick: [false, false],
    };
    BeatBridge.instance.publish(SharedBeat(rows: silent, tempoBpm: 100));
    expect(BeatBridge.instance.current, isNotNull);
    expect(BeatBridge.instance.hasBeat, isFalse); // published but silent
  });

  test('publish → current round-trips the beat + tempo/swing', () {
    final rows = {
      Drum.kick: [true, false],
    };
    BeatBridge.instance.publish(
      SharedBeat(rows: rows, tempoBpm: 90, swing: 0.4, source: 'drumkit'),
    );
    final got = BeatBridge.instance.current!;
    expect(BeatBridge.instance.hasBeat, isTrue);
    expect(got.rows[Drum.kick], [true, false]);
    expect(got.tempoBpm, 90);
    expect(got.swing, 0.4);
    expect(got.source, 'drumkit');
  });
}
