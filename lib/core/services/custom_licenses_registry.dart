// lib/core/services/custom_licenses_registry.dart
//
// Idempotent registration of custom LicenseEntry items for bundled fonts that
// Flutter's showLicensePage() would otherwise miss. The license page auto-
// discovers the LICENSE file of each *pub package*, but a font shipped as an
// *asset* (here: Bravura, bundled by the partitura package) is invisible to it
// unless we register the license text ourselves via LicenseRegistry.addLicense.
//
// Call ensureCustomLicensesRegistered() before opening the About / license
// page (see settings_screen.dart). Mirrors the pattern used in the sibling
// apps (voc's custom_licenses_registry, CrisperWeaver's native_licenses).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

bool _registered = false;

/// Register the SIL OFL for the fonts this app bundles. Safe to call repeatedly.
Future<void> ensureCustomLicensesRegistered() async {
  if (_registered) return;
  _registered = true;

  try {
    // OFL.txt ships inside the partitura package next to Bravura.otf and is
    // declared as a loadable asset there, so we can read it by package path.
    final ofl =
        await rootBundle.loadString('packages/partitura/assets/fonts/OFL.txt');

    LicenseRegistry.addLicense(
      () => Stream<LicenseEntry>.fromIterable([
        LicenseEntryWithLineBreaks(
          const ['Bravura (SMuFL music font)'],
          'Bravura — SMuFL-compliant music notation font\n'
          'Copyright © Steinberg Media Technologies GmbH '
          '(designed by Daniel Spreadbury)\n'
          'Bundled via the partitura package.\n'
          'License: SIL Open Font License, Version 1.1\n\n'
          '------------------------------------------------------------\n\n'
          '$ofl',
        ),
      ]),
    );
  } catch (e) {
    // Don't let a missing/unreadable license file break the license page; the
    // pub-package licenses still show.
    _registered = false; // allow a retry on the next open
    if (kDebugMode) debugPrint('Custom license registration failed: $e');
  }
}
