// ModArchiveKeyStore — BYOK key persistence (SharedPreferences mock).

import 'package:comet_beat/features/library/modarchive_key_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('starts empty', () async {
    final store = ModArchiveKeyStore();
    expect(await store.hasKey(), isFalse);
    expect(await store.read(), isNull);
  });

  test('write/read/clear round-trip; trims and treats blank as clear',
      () async {
    final store = ModArchiveKeyStore();

    await store.write('  abc123  ');
    expect(await store.read(), 'abc123'); // trimmed
    expect(await store.hasKey(), isTrue);

    await store.write('   '); // blank clears
    expect(await store.hasKey(), isFalse);

    await store.write('k2');
    await store.clear();
    expect(await store.read(), isNull);
  });
}
