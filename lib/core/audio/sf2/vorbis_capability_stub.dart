// Web / no-dart:ffi stub for the `.sf3` Vorbis decoder seam. No native decoder
// here, so `.sf3` soundfonts are unsupported (they fall back to the clear
// rejection in Sf2SoundFont.parse). A wasm/glint web path can replace this
// later. See vorbis_capability.dart.

import 'package:comet_beat/core/audio/sf2/sf2.dart' show VorbisDecode;

/// No native Vorbis decoder on this platform → null (`.sf3` unsupported).
VorbisDecode? loadGlintVorbis() => null;
