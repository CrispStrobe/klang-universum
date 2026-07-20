// The process-wide Viterbi override the neural F0 stores read: the override
// wins when set, else the per-model COMET_*_VITERBI env gate applies.

import 'package:comet_beat/core/audio/transcription/f0_decode_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => F0DecodeOptions.viterbi = null);

  test('null override defers to the env gate', () {
    expect(F0DecodeOptions.resolve('K', const {}), isFalse); // unset → off
    expect(F0DecodeOptions.resolve('K', const {'K': '1'}), isTrue);
    expect(F0DecodeOptions.resolve('K', const {'K': '0'}), isFalse);
  });

  test('a set override wins over the env gate, both directions', () {
    F0DecodeOptions.viterbi = true;
    expect(F0DecodeOptions.resolve('K', const {'K': '0'}), isTrue);

    F0DecodeOptions.viterbi = false;
    expect(F0DecodeOptions.resolve('K', const {'K': '1'}), isFalse);
  });
}
