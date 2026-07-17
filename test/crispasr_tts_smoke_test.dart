// REAL end-to-end synthesis through libcrispasr + the on-disk Kokoro model.
// Skips automatically when the native lib / model aren't present (CI, other
// machines), so it never fails a clean checkout — it's the macOS dev proof that
// the Dart FFI → ggml → PCM path works, not a portable unit test.
//
// Point it at your build with env overrides if the defaults don't match:
//   COMET_CRISPASR_LIB, COMET_KOKORO_MODEL, COMET_KOKORO_VOICE_DE
import 'dart:ffi';
import 'dart:io';

import 'package:comet_beat/core/audio/synth.dart' show wavBytes;
import 'package:comet_beat/core/audio/tts/crispasr_tts_backend.dart';
import 'package:crispasr/crispasr.dart';
import 'package:flutter_test/flutter_test.dart';

String _env(String k, String fallback) =>
    Platform.environment[k]?.isNotEmpty == true
        ? Platform.environment[k]!
        : fallback;

void main() {
  final lib = _env(
    'COMET_CRISPASR_LIB',
    '/Users/christianstrobele/code/CrispASR/build/src/libcrispasr.dylib',
  );
  final model = _env(
    'COMET_KOKORO_MODEL',
    '/Users/christianstrobele/code/lego/brickwright-tts-demo/kokoro.gguf',
  );
  final voiceDe = _env(
    'COMET_KOKORO_VOICE_DE',
    '/Users/christianstrobele/Documents/models/whisper_cpp/kokoro-voice-df_eva.gguf',
  );

  final present = File(lib).existsSync() && File(model).existsSync();

  test('the kokoro registry resolves to the published download URL', () {
    if (!File(lib).existsSync()) {
      // ignore: avoid_print
      print('SKIP: libcrispasr not on this machine — dev-only smoke.');
      return;
    }
    final dylib = DynamicLibrary.open(lib);
    final entry = registryLookup('kokoro', lib: dylib);
    expect(entry, isNotNull, reason: 'kokoro missing from the registry');
    expect(entry!.filename, 'kokoro-82m-q8_0.gguf');
    expect(entry.url, contains('huggingface.co/cstr'));
    // The en voice resolves; the de voice URL derives from the same repo.
    final af =
        registryLookupByFilename('kokoro-voice-af_heart.gguf', lib: dylib);
    expect(af?.url, contains('kokoro-voices-GGUF'));
  });

  test(
    'kokoro synthesises real German audio through the FFI backend',
    () {
      if (!present) {
        // ignore: avoid_print
        print('SKIP: libcrispasr/model not on this machine — dev-only smoke.');
        return;
      }
      final pcm = synthesizeKokoroPcm16(
        KokoroSynthRequest(
          libPath: lib,
          modelPath: model,
          voicePath: File(voiceDe).existsSync() ? voiceDe : null,
          text: 'Ein gleichmäßiger Puls ist der Herzschlag der Musik.',
        ),
      );

      expect(pcm, isNotNull, reason: 'synthesis returned null');
      expect(
        pcm!.length,
        greaterThan(24000), // > 1 s @ 24 kHz
        reason: 'suspiciously short audio',
      );
      var peak = 0;
      for (final s in pcm) {
        final a = s.abs();
        if (a > peak) peak = a;
      }
      expect(peak, greaterThan(2000), reason: 'audio is essentially silent');

      // The WAV wrapper the app plays.
      final wav = wavBytes(pcm, sampleRate: 24000);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(wav.length, 44 + pcm.length * 2);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
