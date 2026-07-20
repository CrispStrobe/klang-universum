// VoicePool — the pure round-robin cursor (the audio glue is untested, like
// LoopPlayerService, since it needs the plugin).

import 'package:comet_beat/core/services/voice_pool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('advance cycles through the voices and wraps', () {
    var v = 0;
    final seen = <int>[];
    for (var i = 0; i < 8; i++) {
      seen.add(v);
      v = VoicePool.advance(v, 6);
    }
    // 6 voices → 0..5 then wraps back to 0, 1.
    expect(seen, [0, 1, 2, 3, 4, 5, 0, 1]);
  });

  test('advance is safe for a degenerate size', () {
    expect(VoicePool.advance(3, 0), 0);
  });
}
