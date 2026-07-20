// Web / no-dart:io fallback: no CrispASR FFI. Matches the IO signature.

import 'package:comet_beat/core/audio/transcription/stems.dart' show Separator;

Future<Separator?> loadCrispasrFfiSeparator({bool download = false}) async =>
    null;
