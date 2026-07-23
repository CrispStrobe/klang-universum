// Resolving the app's global playback voice from a persisted id.
//
// The Settings "Instrument Sound" and AudioService speak in a single `voiceId`
// string. The four additive ids (piano/cello/flute/musicBox) map to the
// [Instrument] enum with NO [TrackerInstrument] override — i.e. the classic
// additive playback path, unchanged. Any other [kTrackerInstruments] id
// (chiptune sfxr, Karplus pluck, FM, subtractive) builds a procedural voice
// override. This file is Flutter-free (no l10n / widgets) so it stays in core.

import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/audio/tracker_engine.dart';

/// The additive voice ids that map straight to the [Instrument] enum (the
/// classic path — [AudioService.voice] stays null for these, byte-for-byte
/// unchanged). Everything else in [kTrackerInstruments] is a procedural override.
final Set<String> kAdditiveVoiceIds =
    Instrument.values.map((e) => e.name).toSet();

/// Resolve a built-in [voiceId] into what AudioService needs: the additive
/// [instrument] timbre and an optional [voice] override. Additive ids → the
/// enum + null override; procedural ids → piano fallback enum + a built voice;
/// an unknown id → the default piano additive voice.
({Instrument instrument, TrackerInstrument? voice}) resolveVoiceSync(
  String voiceId,
) {
  final enumV = Instrument.values.asNameMap()[voiceId];
  if (enumV != null) return (instrument: enumV, voice: null);
  for (final o in kTrackerInstruments) {
    if (o.id == voiceId) {
      return (instrument: Instrument.piano, voice: o.build());
    }
  }
  return (instrument: Instrument.piano, voice: null);
}

/// Whether [voiceId] names a known built-in voice (additive or procedural).
bool isBuiltInVoiceId(String voiceId) =>
    kAdditiveVoiceIds.contains(voiceId) ||
    kTrackerInstruments.any((o) => o.id == voiceId);

/// Prefix marking a voice id that refers to a saved library instrument (by
/// name), e.g. `lib:My Cello`. These can't be resolved by [resolveVoiceSync]
/// (they need the InstrumentLibraryStore) — main.dart resolves them at startup.
const kLibraryVoicePrefix = 'lib:';

/// Builds a library voice id from a saved instrument [name].
String libraryVoiceId(String name) => '$kLibraryVoicePrefix$name';

/// The saved-instrument name a [voiceId] refers to, or null if it's not a
/// library voice.
String? libraryVoiceName(String voiceId) =>
    voiceId.startsWith(kLibraryVoicePrefix)
        ? voiceId.substring(kLibraryVoicePrefix.length)
        : null;
