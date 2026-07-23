// Shared type for the batch SFZ-instrument installer.

import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerInstrument;

/// A locally-installed SFZ instrument: the built voice, where its `.sfz` is
/// cached, and how many files were fetched (SFZ + samples).
class InstalledInstrument {
  const InstalledInstrument({
    required this.instrument,
    required this.sfzPath,
    required this.fileCount,
  });
  final TrackerInstrument instrument;
  final String sfzPath;
  final int fileCount;
}
