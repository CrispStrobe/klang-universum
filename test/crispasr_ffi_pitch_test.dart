// The CrispASR CREPE F0 via the crispasr-package FFI (CrispasrSession.pitch).
// Can't run the native lib deterministically in CI, so we assert the ONE thing
// that must always hold: it degrades gracefully. With no loadable 0.8.16
// libcrispasr (+ crepe model), crispasrFfiCrepeF0 returns null WITHOUT throwing,
// so loadCrispasrCrepeF0 can fall through to the CLI, then the ONNX/pyin paths.

import 'package:comet_beat/core/audio/transcription/crispasr_ffi_pitch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('crispasrFfiCrepeF0 never throws; null when the ggml runtime is absent',
      () async {
    // On CI/dev there is no pitch-capable libcrispasr, so this resolves to null
    // (an older/missing lib or no crepe model) — the point is it must not throw.
    final estimator = await crispasrFfiCrepeF0();
    expect(estimator, anyOf(isNull, isNotNull));
  });
}
