// Locate the freshly-built native library for tests. Prefers the full `aec`
// library (which has aec_engine_* + aec_dsp_*); falls back to `aec_dsp`.
import 'dart:io';

String? resolveAecLibrary({bool requireEngine = false}) {
  final env = Platform.environment['AEC_LIBRARY_PATH'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) return env;
  final ext = Platform.isMacOS
      ? 'dylib'
      : Platform.isWindows
          ? 'dll'
          : 'so';
  final prefix = Platform.isWindows ? '' : 'lib';
  final names = requireEngine ? ['aec'] : ['aec', 'aec_dsp'];
  for (final name in names) {
    for (final dir in [
      'build',
      'native/aec/build',
      'build/Release',
      'build/Debug',
    ]) {
      final p = '$dir/$prefix$name.$ext';
      if (File(p).existsSync()) return p;
    }
  }
  return null;
}
