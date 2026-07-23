// Downloads manager — see what CometBeat has cached on disk (AI models,
// SoundFonts, instrument samples), how big it is, and remove it to free space.
// Everything downloaded on demand lives under one root
// (`$HOME/.cache/comet_beat/<category>/`), so this scans that root. dart:io only
// — on web there are no local downloads, so the stub reports none.
export 'downloads_manager_stub.dart'
    if (dart.library.io) 'downloads_manager_io.dart';
export 'downloads_manager_types.dart';
