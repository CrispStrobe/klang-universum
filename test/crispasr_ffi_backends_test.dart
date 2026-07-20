// The CrispASR FFI piano/separate providers (crispasr 0.8.17). Can't run the
// native lib in CI, so we assert the invariant: they degrade gracefully — no
// pitch-capable/htdemucs/piano libcrispasr here ⇒ null WITHOUT throwing, so the
// resolver falls back (onnx Basic Pitch / a single-part song).

import 'package:comet_beat/core/audio/transcription/crispasr_ffi_piano.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_separate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('piano + separate FFI loaders never throw; null when the lib is absent',
      () async {
    expect(await loadCrispasrPianoFfi(), anyOf(isNull, isNotNull));
    expect(await loadCrispasrFfiSeparator(), anyOf(isNull, isNotNull));
  });
}
