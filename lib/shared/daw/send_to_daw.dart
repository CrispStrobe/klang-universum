// lib/shared/daw/send_to_daw.dart
//
// The one-liner every module uses to hand its current model to the shared
// Multitrack (DAW) as a clip. Each module builds its own `ClipSource` (a
// DrumSource / GrooveSource / ScoreSource / TrackerSource — see
// core/audio/daw_sources.dart) and calls this; the arranger accumulates them.

import 'package:comet_beat/core/audio/daw_timeline.dart' show ClipSource;
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Send [source] to the shared Multitrack (on [track]) and confirm with a
/// snackbar. Reads [DawService] from the widget tree.
void sendToMultitrack(
  BuildContext context,
  ClipSource source, {
  int track = 0,
}) {
  context.read<DawService>().addClip(source, track: track);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(AppLocalizations.of(context)!.dawSent)),
  );
}
