// The bundled CC0 sample library — a small, license-clean set of recorded
// one-shots (public-domain VCSL percussion) the tracker can drop into an
// instrument slot, alongside the procedural voices in [kTrackerInstruments].
// See assets/sounds/percussion/LICENSE.txt (all CC0 / public domain).
//
// This file is Flutter-free: it turns already-loaded WAV bytes into a
// [SampleInstrument]. The app reads the asset bytes (rootBundle) and calls
// [sampleInstrumentFromWavBytes]; tests read the file straight from disk. That
// keeps the decode path unit-testable without a device or asset bundle.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/wav_io.dart';

/// A bundled sound asset: where it lives, how it's shown, and the MIDI note the
/// recording represents (so resampling plays it in tune). Percussion uses a
/// nominal [baseMidi] — it's played at one pitch.
class BundledSampleInfo {
  const BundledSampleInfo({
    required this.id,
    required this.assetPath,
    required this.category,
    this.baseMidi = 60,
  });

  final String id;
  final String assetPath;
  final SoundCategory category;
  final int baseMidi;
}

/// The bundled CC0 percussion kit (VCSL, public domain). All under
/// `assets/sounds/percussion/` and registered in `pubspec.yaml`.
const kBundledPercussion = <BundledSampleInfo>[
  BundledSampleInfo(
    id: 'vcsl_snare',
    assetPath: 'assets/sounds/percussion/snare.wav',
    category: SoundCategory.drum,
  ),
  BundledSampleInfo(
    id: 'vcsl_rim',
    assetPath: 'assets/sounds/percussion/rim.wav',
    category: SoundCategory.drum,
  ),
  BundledSampleInfo(
    id: 'vcsl_shaker',
    assetPath: 'assets/sounds/percussion/shaker.wav',
    category: SoundCategory.drum,
  ),
  BundledSampleInfo(
    id: 'vcsl_clave',
    assetPath: 'assets/sounds/percussion/clave.wav',
    category: SoundCategory.drum,
  ),
];

/// Decode PCM16 WAV [bytes] into a [SampleInstrument] tagged [id], resampled to
/// the engine rate (so a file recorded at any rate plays at the right speed).
/// [baseMidi] is the note the recording represents. Pure Dart — no Flutter, no
/// asset bundle.
SampleInstrument sampleInstrumentFromWavBytes(
  Uint8List bytes, {
  required String id,
  int baseMidi = 60,
}) {
  final wav = readWavPcm16(bytes);
  var mono = wavToMonoFloat(wav);
  if (wav.sampleRate > 0 && wav.sampleRate != kSampleRate) {
    // resampleCubic(src, ratio) yields src.length / ratio output samples, so a
    // ratio of srcRate/engineRate rescales the file to the engine rate.
    mono = resampleCubic(mono, wav.sampleRate / kSampleRate);
  }
  return SampleInstrument(id, mono, baseMidi: baseMidi);
}

/// Build a [SampleInstrument] from a bundled [info] and its already-loaded
/// [bytes] (the app fetches the bytes via `rootBundle.load(info.assetPath)`).
SampleInstrument bundledSampleInstrument(
  BundledSampleInfo info,
  Uint8List bytes,
) =>
    sampleInstrumentFromWavBytes(bytes, id: info.id, baseMidi: info.baseMidi);
