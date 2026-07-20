// MelodyBridge — the pitched shared-tune backbone.

import 'package:comet_beat/core/audio/loop_engine.dart' show PatternCell;
import 'package:comet_beat/core/services/melody_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(MelodyBridge.instance.clear);

  test('publish → current + hasMelody; clear resets', () {
    expect(MelodyBridge.instance.hasMelody, isFalse);

    final m = SharedMelody(
      cells: const <PatternCell>[
        (midis: [60], steps: 2),
        (midis: null, steps: 2),
        (midis: [67], steps: 4),
      ],
      tempoBpm: 100,
      instrument: 'flute',
      source: 'loopmixer',
    );
    MelodyBridge.instance.publish(m);

    expect(MelodyBridge.instance.hasMelody, isTrue);
    expect(MelodyBridge.instance.current!.instrument, 'flute');
    expect(MelodyBridge.instance.current!.toCells(), hasLength(3));

    MelodyBridge.instance.clear();
    expect(MelodyBridge.instance.hasMelody, isFalse);
    expect(MelodyBridge.instance.current, isNull);
  });

  test('an all-rest tune counts as empty (not offered)', () {
    MelodyBridge.instance.publish(
      SharedMelody(
        cells: const <PatternCell>[(midis: null, steps: 16)],
        tempoBpm: 100,
      ),
    );
    expect(MelodyBridge.instance.current, isNotNull);
    expect(MelodyBridge.instance.hasMelody, isFalse); // empty → not offered
  });

  test('cells are unmodifiable (a snapshot)', () {
    final m = SharedMelody(
      cells: const <PatternCell>[
        (midis: [60], steps: 16),
      ],
      tempoBpm: 100,
    );
    expect(() => m.cells.add((midis: null, steps: 1)), throwsUnsupportedError);
  });
}
