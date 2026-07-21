// Web / no-dart:io stub for OMR import — recognition needs the native ggml
// engine, which isn't available here.
import 'dart:typed_data';

import 'package:crisp_notation/crisp_notation.dart' show Score;

/// OMR is never available on this platform.
bool omrAvailable() => false;

/// The on-disk model, absent here.
Future<String?> omrModelPath({bool download = false}) async => null;

/// Always null — no native recognition on web.
Future<Score?> recognizeSheetMusic(
  Uint8List imageBytes, {
  bool download = false,
  void Function(String message)? onStatus,
}) async =>
    null;
