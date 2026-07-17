// Driver for the App Store screenshot capture (run via `flutter drive`).
// Saves each `binding.takeScreenshot(name)` payload to screenshots/<name>.png.
// See integration_test/screenshots_test.dart and .github/workflows/screenshots.yml.
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (
      String name,
      List<int> bytes, [
      Map<String, Object?>? args,
    ]) async {
      final file = File('screenshots/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      return true;
    },
  );
}
