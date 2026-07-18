// The Sound Lab's "My Sounds" preset store — the pure encode/decode pair and
// the SharedPreferences-backed round-trip (mocked, no platform).

import 'package:comet_beat/features/sound_lab/sfx_engine.dart';
import 'package:comet_beat/features/sound_lab/sound_preset_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final coin = kSfxPresets['coin']!;

  group('encode/decode (pure)', () {
    test('round-trips a preset list with its params', () {
      final raw = encodePresets([
        SoundPreset('zap', coin),
        SoundPreset('boom', kSfxPresets['explosion']!),
      ]);
      final back = decodePresets(raw);
      expect(back.map((p) => p.name), ['zap', 'boom']);
      expect(back.first.params.toJson(), coin.toJson());
    });

    test('blank / null / garbage decodes to empty, never throws', () {
      expect(decodePresets(null), isEmpty);
      expect(decodePresets(''), isEmpty);
      expect(decodePresets('not json'), isEmpty);
      expect(decodePresets('{"not":"a list"}'), isEmpty);
    });

    test('skips a malformed entry but keeps the good ones', () {
      final raw = '[{"name":"ok","params":${_paramsJson(coin)}},'
          '{"name":123},{"garbage":true}]';
      final back = decodePresets(raw);
      expect(back.map((p) => p.name), ['ok']);
    });
  });

  group('SoundPresetStore (mocked prefs)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('save persists and load recalls', () async {
      final store = SoundPresetStore();
      expect(await store.load(), isEmpty);
      await store.save(SoundPreset('zap', coin));
      final reloaded = await SoundPresetStore().load(); // fresh instance
      expect(reloaded.single.name, 'zap');
    });

    test('saving under an existing name overwrites, not duplicates', () async {
      final store = SoundPresetStore();
      await store.save(SoundPreset('zap', coin));
      final after = await store.save(
        SoundPreset('zap', kSfxPresets['explosion']!),
      );
      expect(after.length, 1);
      expect(after.single.params.toJson(), kSfxPresets['explosion']!.toJson());
    });

    test('delete removes by name', () async {
      final store = SoundPresetStore();
      await store.save(SoundPreset('a', coin));
      await store.save(SoundPreset('b', coin));
      final after = await store.delete('a');
      expect(after.map((p) => p.name), ['b']);
    });
  });
}

String _paramsJson(SfxParams p) {
  final j = p.toJson();
  final pairs = j.entries.map((e) {
    final v = e.value;
    return '"${e.key}":${v is String ? '"$v"' : v}';
  }).join(',');
  return '{$pairs}';
}
