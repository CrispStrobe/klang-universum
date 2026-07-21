// Web / no-dart:io stub: no native library, so OMR is unavailable here.

import 'package:crisp_notation/crisp_notation.dart' show OmrEngine;

/// Always null off the native path (web) — the caller then reports that on-device
/// OMR isn't available and the user can paste tokens / import a symbolic file.
Future<OmrEngine?> crispembedFfiOmr({bool download = false}) async => null;
