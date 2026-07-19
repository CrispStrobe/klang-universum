// Headless "load a SoundFont" facade — the whole capability behind a UI's
// "Load SoundFont" button, with zero Flutter/screen deps so it's unit-testable
// and reusable from any screen.
//
// Pick bytes → [loadSoundFont] parses them (uncompressed `.sf2` directly, or a
// compressed `.sf3` via the platform glint Vorbis decoder, auto-selected) into
// a browsable [LoadedSoundFont]; the UI lists [LoadedSoundFont.presets], and
// [soundFontInstrument] turns a chosen preset into a playable tracker
// instrument (the same multi-sample, key/velocity-split voice the SF2 reader
// builds). Friendly, catchable [SoundFontLoadException]s replace the reader's
// raw FormatExceptions so the UI can just show `e.message`.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/sf2.dart';
import 'package:comet_beat/core/audio/sf2/vorbis_capability.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';

/// A parsed SoundFont ready to browse: the backing [font] plus its presets in a
/// stable display order. [compressed] is true when it was a `.sf3` (decoded via
/// the Vorbis seam).
class LoadedSoundFont {
  LoadedSoundFont(this.font, {required this.compressed})
      : presets = _sorted(font.presets);

  final Sf2SoundFont font;
  final bool compressed;

  /// Presets sorted by bank then program (General MIDI order) so the browse
  /// list is stable and melodic voices precede the bank-128 drum kits.
  final List<Sf2Preset> presets;

  static List<Sf2Preset> _sorted(List<Sf2Preset> ps) {
    final out = [...ps];
    out.sort(
      (a, b) => a.bank != b.bank ? a.bank - b.bank : a.program - b.program,
    );
    return out;
  }
}

/// A load failure with a short, user-showable [message] (the UI shows it
/// directly — no stack traces or raw format details).
class SoundFontLoadException implements Exception {
  SoundFontLoadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Parse SoundFont [bytes] into a browsable [LoadedSoundFont]. Handles both an
/// uncompressed `.sf2` and a compressed `.sf3`: for `.sf3` it uses [vorbis], or
/// (default) the platform glint decoder via [loadGlintVorbis]. If the bytes are
/// a `.sf3` and no decoder is available, throws a clear [SoundFontLoadException]
/// telling the user to try a `.sf2` — never garbage PCM.
LoadedSoundFont loadSoundFont(Uint8List bytes, {VorbisDecode? vorbis}) {
  final compressed = sf2IsCompressed(bytes);
  final decode = vorbis ?? (compressed ? loadGlintVorbis() : null);
  if (compressed && decode == null) {
    throw SoundFontLoadException(
      'This is a compressed .sf3 SoundFont, which needs a Vorbis decoder that '
      'is not available here. Try an uncompressed .sf2 file.',
    );
  }
  final Sf2SoundFont font;
  try {
    font = Sf2SoundFont.parse(bytes, vorbis: decode);
  } on FormatException catch (e) {
    throw SoundFontLoadException('Not a valid SoundFont: ${e.message}');
  }
  if (font.presets.isEmpty) {
    throw SoundFontLoadException('No instruments found in this SoundFont.');
  }
  return LoadedSoundFont(font, compressed: compressed);
}

/// Build a playable tracker instrument from a chosen [preset] of [loaded] — the
/// full key/velocity-split GM voice. [id] defaults to a stable per-preset id.
TrackerInstrument soundFontInstrument(
  LoadedSoundFont loaded,
  Sf2Preset preset, {
  String? id,
}) {
  return sf2InstrumentFromPreset(
    loaded.font,
    preset,
    id: id ?? soundFontInstrumentId(preset),
  );
}

/// A stable instrument id for a preset (bank/program keyed, so re-loading the
/// same font+preset yields the same id → a stable stem cache).
String soundFontInstrumentId(Sf2Preset p) =>
    'sf2.${p.bank}.${p.program}.${p.name}';

/// A short human label for a preset in a browse list, e.g. "GM 40 · Violin" or
/// "Drum · Standard" (bank 128 = the GM percussion bank).
String soundFontPresetLabel(Sf2Preset p) {
  final kind = p.bank == 128 ? 'Drum' : 'GM ${p.program}';
  final name = p.name.trim().isEmpty ? 'Preset ${p.program}' : p.name.trim();
  return '$kind · $name';
}
