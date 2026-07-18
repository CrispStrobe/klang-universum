// Drumkit / BoomBox — the step beat-grid over a shared DrumRowsPattern.
// Audio is a no-op in the headless binding; assertions are on the grid + state.

import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/features/games/drums/drumkit_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

DrumkitTester _kit(WidgetTester tester) =>
    tester.state<State<DrumkitScreen>>(find.byType(DrumkitScreen))
        as DrumkitTester;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('toggling grid cells builds the beat', (tester) async {
    await pumpGame(tester, const DrumkitScreen());
    final kit = _kit(tester);
    expect(kit.steps, 16);
    expect(kit.hitCount, 0);

    kit.toggle(Drum.kick, 0);
    kit.toggle(Drum.kick, 8);
    kit.toggle(Drum.snare, 4);
    await tester.pump();

    expect(kit.hitCount, 3);
    expect(kit.cellAt(Drum.kick, 0), isTrue);
    expect(kit.cellAt(Drum.kick, 8), isTrue);
    expect(kit.cellAt(Drum.snare, 4), isTrue);
    expect(kit.cellAt(Drum.hat, 0), isFalse);

    kit.toggle(Drum.kick, 0); // off again
    await tester.pump();
    expect(kit.hitCount, 2);
  });

  testWidgets('play/stop + clear + tempo + pad tap do not crash',
      (tester) async {
    await pumpGame(tester, const DrumkitScreen());
    final kit = _kit(tester);
    kit.toggle(Drum.kick, 0);
    kit.setTempo(120);
    expect(kit.tempo, 120);

    kit.tapPad(Drum.snare); // one-shot audition (no-op audio)
    kit.togglePlay();
    await tester.pump();
    kit.stop();
    await tester.pump();
    expect(kit.isPlaying, isFalse);

    kit.clear();
    await tester.pump();
    expect(kit.hitCount, 0);
    expect(tester.takeException(), isNull);
  });
}
