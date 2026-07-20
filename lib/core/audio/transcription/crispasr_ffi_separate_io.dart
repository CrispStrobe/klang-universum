// Native CrispASR ggml source separation (CrispasrSession.separate, crispasr
// 0.8.17+). The Separator seam takes mono @ the input rate; CrispASR wants
// INTERLEAVED STEREO @ its separateSampleRate (44.1 kHz for htdemucs), so we
// resample→duplicate in, and mono-mix→resample-back out. dart:io only. Null when
// the ggml runtime/model isn't available → the whole-song pipeline falls back
// to the CLI separator, then a single part.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_session_io.dart';
import 'package:comet_beat/core/audio/transcription/stems.dart'
    show Separator, Stems;

const Stems _empty = (vocals: null, bass: null, drums: null, other: null);

/// A CrispASR-FFI htdemucs [Separator], or null when the model/lib isn't here.
Future<Separator?> loadCrispasrFfiSeparator({bool download = false}) async {
  final session = openCrispasrSession('htdemucs', download: download);
  if (session == null) return null;
  final sr = session.separateSampleRate; // 44100
  return (Float64List mono, int sampleRate) async {
    if (mono.isEmpty) return _empty;
    // mono @ input rate → mono @ sr → interleaved stereo (L=R).
    final at = sampleRate == sr ? mono : resampleLinear(mono, sampleRate / sr);
    final stereo = Float32List(at.length * 2);
    for (var i = 0; i < at.length; i++) {
      final v = at[i].toDouble();
      stereo[2 * i] = v;
      stereo[2 * i + 1] = v;
    }
    try {
      final stems = session.separate(stereo);
      // Interleaved-stereo stem → mono @ input rate.
      Float64List? mono0(String name) {
        for (final s in stems) {
          if (s.name == name) {
            final n = s.pcm.length ~/ 2;
            final m = Float64List(n);
            for (var i = 0; i < n; i++) {
              m[i] = (s.pcm[2 * i] + s.pcm[2 * i + 1]) / 2;
            }
            return sampleRate == sr ? m : resampleLinear(m, sr / sampleRate);
          }
        }
        return null;
      }

      return (
        vocals: mono0('vocals'),
        bass: mono0('bass'),
        drums: mono0('drums'),
        // RoFormer labels its non-vocal stem 'instrumental'.
        other: mono0('other') ?? mono0('instrumental'),
      );
    } catch (_) {
      return _empty;
    }
  };
}
