// A shared marker for OMR engines that own native resources.

import 'package:crisp_notation/crisp_notation.dart' show OmrEngine;

/// An [OmrEngine] that holds a native model/session and must be freed with
/// [dispose] once recognition is done. The pure-Dart / injected-fake engines a
/// caller might pass are plain [OmrEngine]s (nothing to free); only the native
/// FFI engine is disposable, so [omrImageToScore] frees it via this interface.
abstract class DisposableOmrEngine implements OmrEngine {
  /// Frees the native model. Idempotent.
  void dispose();
}
