// The .sf3 Vorbis platform seam: on native (the VM test host) it degrades
// gracefully when the glint library isn't bundled (returns null, no throw), and
// decodes when pointed at a real libglint. The web build gets the null stub.

@TestOn('vm')
library;

import 'dart:io';

import 'package:comet_beat/core/audio/sf2/vorbis_capability_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missing glint library → null, no crash', () {
    // No library bundled in the test env → graceful null (.sf3 stays rejected).
    expect(loadGlintVorbis(), isNull);
    // A bogus path is caught, not thrown.
    expect(loadGlintVorbis(libraryPath: '/no/such/libglint.dylib'), isNull);
  });

  test('a real libglint (if built locally) yields a working decoder', () {
    // Dev check: if the glint dylib is present, the seam returns a usable
    // VorbisDecode. Skipped when glint isn't built (CI has no glint).
    final lib = File(
      '${Platform.environment['HOME']}/code/glint/build/libglint.dylib',
    );
    if (!lib.existsSync()) {
      return; // glint not built here — nothing to assert
    }
    final decode = loadGlintVorbis(libraryPath: lib.path);
    expect(decode, isNotNull);
  });
}
