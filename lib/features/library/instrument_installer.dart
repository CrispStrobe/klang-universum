// Batch SFZ-instrument installer — for a catalog SFZ instrument (dozens/hundreds
// of samples), fetch the `.sfz`, download its ENTIRE sample tree from HF, cache
// it on disk (under $HOME/.cache/comet_beat/instruments/<id>/, which the
// Downloads manager surfaces + can free), and load it into a playable voice.
//
// dart:io only (the cache is a real directory tree); the web stub reports
// unsupported. NB: loadSfz decodes WAV samples; FLAC-sampled instruments still
// download + cache but won't play until a FLAC decoder lands.
export 'instrument_installer_stub.dart'
    if (dart.library.io) 'instrument_installer_io.dart';
export 'instrument_installer_types.dart';
