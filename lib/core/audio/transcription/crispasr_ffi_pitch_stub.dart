// Web / no-dart:io fallback: no CrispASR FFI. Signature matches the IO impl.

import 'package:comet_beat/core/audio/transcription/route.dart'
    show F0Estimator;

Future<F0Estimator?> crispasrFfiCrepeF0({bool download = false}) async => null;
