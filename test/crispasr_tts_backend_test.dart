// CrispAsrTtsBackend + KokoroModelStore: resolution + playback wiring, driven
// through a fake synthesis seam (no native libcrispasr, no isolate) so it runs
// anywhere including CI.
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tts/crispasr_tts_backend.dart';
import 'package:comet_beat/core/audio/tts/kokoro_model_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late String libFile;
  late String modelFile;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('tts_test_');
    // Stand-ins so the store's file-existence checks pass without a real engine.
    libFile = '${tmp.path}/libcrispasr.dylib';
    modelFile = '${tmp.path}/kokoro-82m-f16.gguf';
    File(libFile).writeAsBytesSync([0]);
    File(modelFile).writeAsBytesSync([0]);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  KokoroModelStore storeWith({bool withModel = true}) => KokoroModelStore(
        cacheDir: tmp.path,
        libPathOverride: libFile,
        modelPathOverride: withModel ? modelFile : '${tmp.path}/missing.gguf',
      );

  test('isReady is true only when lib + model files exist', () async {
    expect(await storeWith().isReady(), isTrue);
    expect(await storeWith(withModel: false).isReady(), isFalse);
  });

  test('ensureModel is a no-op without a base URL (stays unavailable)',
      () async {
    final store = KokoroModelStore(
      cacheDir: tmp.path,
      libPathOverride: libFile,
      modelPathOverride: '${tmp.path}/none.gguf',
    );
    await store.ensureModel('de');
    expect(await store.isReady(), isFalse); // nothing downloaded
  });

  test('speak synthesises then plays a valid WAV', () async {
    Uint8List? played;
    final backend = CrispAsrTtsBackend(
      store: storeWith(),
      play: (wav) async => played = wav,
      // Fake synthesis: 100 samples of PCM16 — no native call.
      runSynthesis: (req) async => Int16List.fromList(
        List<int>.generate(100, (i) => (i - 50) * 100),
      ),
    );

    expect(await backend.isAvailable(), isTrue);
    await backend.speak('Ein Test', langCode: 'de');

    expect(played, isNotNull);
    // RIFF/WAVE header + 44-byte header + 100*2 sample bytes.
    expect(String.fromCharCodes(played!.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(played!.sublist(8, 12)), 'WAVE');
    expect(played!.length, 44 + 100 * 2);
  });

  test('speak plays nothing when the model is unavailable', () async {
    var playCalls = 0;
    final backend = CrispAsrTtsBackend(
      store: storeWith(withModel: false),
      play: (wav) async => playCalls++,
      runSynthesis: (req) async => Int16List.fromList([1, 2, 3]),
    );
    await backend.speak('anything', langCode: 'en');
    expect(playCalls, 0);
  });

  test('a NaN/empty synthesis result does not play', () async {
    var playCalls = 0;
    final backend = CrispAsrTtsBackend(
      store: storeWith(),
      play: (wav) async => playCalls++,
      runSynthesis: (req) async => null, // decode failed
    );
    await backend.speak('x', langCode: 'en');
    expect(playCalls, 0);
  });

  test('the de voice pack is picked for a de-DE locale tag', () async {
    // Drop a de voice file so resolve() surfaces it.
    final voice = '${tmp.path}/kokoro-voice-df_eva.gguf';
    File(voice).writeAsBytesSync([0]);
    KokoroSynthRequest? seen;
    final backend = CrispAsrTtsBackend(
      store: storeWith(),
      play: (_) async {},
      runSynthesis: (req) async {
        seen = req;
        return Int16List.fromList([0]);
      },
    );
    await backend.speak('Hallo', langCode: 'de-DE');
    expect(seen?.voicePath, endsWith('df_eva.gguf'));
  });
}
