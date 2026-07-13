// Locates and opens the compiled native AEC library.
//
// Resolution order:
//   1. an explicit path passed to [openAecLibrary];
//   2. the AEC_LIBRARY_PATH environment variable (used by the offline test,
//      which points it at the freshly-built dylib under native/aec/build/);
//   3. the platform-conventional library name (once wrapped as a real Flutter
//      FFI plugin, the loader resolves the bundled library by process/name).
//
// Kept tiny and dependency-free so both the low-level [AecDsp] and the full
// [AecEngine] share one loader.

import 'dart:ffi';
import 'dart:io';

/// The bundled Flutter FFI plugin library name (matches OUTPUT_NAME in
/// src/CMakeLists.txt and the podspec module).
const String _libName = 'aec_fullduplex';

DynamicLibrary openAecLibrary([String? explicitPath]) {
  // Tests/CLI point straight at a freshly-built dylib.
  final path = explicitPath ?? Platform.environment['AEC_LIBRARY_PATH'];
  if (path != null && path.isNotEmpty) {
    return DynamicLibrary.open(path);
  }
  // Bundled-plugin resolution (the normal in-app path).
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  // Symbols may be linked directly into the host process.
  return DynamicLibrary.process();
}
