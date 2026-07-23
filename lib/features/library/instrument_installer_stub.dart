// Web stub — no on-disk sample cache, so batch install is unsupported.
import 'package:comet_beat/features/library/content_source.dart' show HttpGet;
import 'package:comet_beat/features/library/instrument_installer_types.dart';

bool get instrumentInstallSupported => false;

Future<InstalledInstrument?> installSfzInstrument({
  required String sfzUrl,
  required String name,
  required HttpGet http,
  void Function(int done, int total)? onProgress,
  String? cacheDirOverride,
}) async =>
    null;
