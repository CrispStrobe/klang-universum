// CrispAsrTtsBackend: playback wiring, download-gating and locale→voice routing,
// driven through the injected job seam (no native libcrispasr, no isolate) so it
// runs anywhere including CI.
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tts/crispasr_tts_backend.dart';
import 'package:comet_beat/core/audio/tts/kokoro_model_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('speak synthesises then plays a valid WAV', () async {
    Uint8List? played;
    final backend = CrispAsrTtsBackend(
      store: KokoroModelStore(),
      play: (wav) async => played = wav,
      // Fake job: 100 samples of PCM16, no native call.
      runJob: (job) async =>
          Int16List.fromList(List<int>.generate(100, (i) => (i - 50) * 100)),
    );

    await backend.speak('Ein Test', langCode: 'de');

    expect(played, isNotNull);
    expect(String.fromCharCodes(played!.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(played!.sublist(8, 12)), 'WAVE');
    expect(played!.length, 44 + 100 * 2);
  });

  test('playback never asks the job to download', () async {
    KokoroJob? seen;
    final backend = CrispAsrTtsBackend(
      store: KokoroModelStore(),
      play: (_) async {},
      runJob: (job) async {
        seen = job;
        return Int16List.fromList([0]);
      },
    );
    await backend.speak('hi', langCode: 'en');
    expect(seen?.download, isFalse);
  });

  test('download() runs a download-enabled warmup job', () async {
    KokoroJob? seen;
    final backend = CrispAsrTtsBackend(
      store: KokoroModelStore(),
      play: (_) async {},
      runJob: (job) async {
        seen = job;
        return Int16List(0); // warmup returns empty
      },
    );
    await backend.download('de-DE');
    expect(seen?.download, isTrue);
    expect(seen?.text, isNull); // warmup, not synthesis
    expect(seen?.lang, 'de');
  });

  test('locale tag is normalised to a base language for the voice', () async {
    KokoroJob? seen;
    final backend = CrispAsrTtsBackend(
      store: KokoroModelStore(),
      play: (_) async {},
      runJob: (job) async {
        seen = job;
        return Int16List.fromList([0]);
      },
    );
    await backend.speak('Hallo', langCode: 'de-DE');
    expect(seen?.lang, 'de');
    expect(
      KokoroModelStore.voiceFileFor('de'),
      'kokoro-voice-df_victoria.gguf',
    );
    expect(KokoroModelStore.voiceFileFor('en'), 'kokoro-voice-af_heart.gguf');
  });

  test('a NaN/empty synthesis result does not play', () async {
    var playCalls = 0;
    final backend = CrispAsrTtsBackend(
      store: KokoroModelStore(),
      play: (_) async => playCalls++,
      runJob: (job) async => null, // decode failed
    );
    await backend.speak('x', langCode: 'en');
    expect(playCalls, 0);
  });
}
