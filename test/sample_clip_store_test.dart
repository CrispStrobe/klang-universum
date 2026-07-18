// The "My Samples" clip store — pure encode/decode (base64 PCM) + the
// SharedPreferences-backed round-trip (mocked).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Float64List _tone(int n) => Float64List.fromList([
      for (var i = 0; i < n; i++) 0.5 * math.sin(2 * math.pi * 220 * i / 44100),
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('encode/decode (pure)', () {
    test('round-trips a clip near-losslessly (16-bit quantization)', () {
      final clip = SampleClip(
        name: 'a',
        sampleRate: 22050,
        pcm: _tone(256),
        source: 'test',
      );
      final back = decodeClips(encodeClips([clip])).single;
      expect(back.name, 'a');
      expect(back.sampleRate, 22050);
      expect(back.source, 'test');
      expect(back.pcm.length, 256);
      // Quantized to 16-bit, so within one LSB.
      for (var i = 0; i < 256; i++) {
        expect((back.pcm[i] - clip.pcm[i]).abs(), lessThan(1 / 32000));
      }
    });

    test('blank / garbage decodes to empty, never throws', () {
      expect(decodeClips(null), isEmpty);
      expect(decodeClips(''), isEmpty);
      expect(decodeClips('nope'), isEmpty);
      expect(decodeClips('[{"name":1}]'), isEmpty); // bad entry skipped
    });
  });

  group('SampleClipStore (mocked prefs)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('save persists and a fresh store recalls', () async {
      await SampleClipStore().save(
        SampleClip(name: 'zap', sampleRate: 8000, pcm: _tone(64)),
      );
      final reloaded = await SampleClipStore().load();
      expect(reloaded.single.name, 'zap');
      expect(reloaded.single.pcm.length, 64);
    });

    test('save under an existing name overwrites', () async {
      final store = SampleClipStore();
      await store.save(SampleClip(name: 'x', sampleRate: 8000, pcm: _tone(32)));
      final after = await store.save(
        SampleClip(name: 'x', sampleRate: 8000, pcm: _tone(99)),
      );
      expect(after.length, 1);
      expect(after.single.pcm.length, 99);
    });

    test('delete removes by name', () async {
      final store = SampleClipStore();
      await store.save(SampleClip(name: 'a', sampleRate: 8000, pcm: _tone(8)));
      await store.save(SampleClip(name: 'b', sampleRate: 8000, pcm: _tone(8)));
      expect((await store.delete('a')).map((c) => c.name), ['b']);
    });
  });
}
