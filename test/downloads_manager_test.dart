// The downloads manager: size formatting (pure), and a native scan/clear
// round-trip over a temp cache root (models + soundfonts subdirs).

import 'dart:io';

import 'package:comet_beat/features/settings/downloads_manager.dart';
import 'package:flutter_test/flutter_test.dart';

DownloadCategory _cat(int bytes) =>
    DownloadCategory(id: '', label: '', bytes: bytes, items: 0, path: '');

void main() {
  group('sizeLabel', () {
    test('scales bytes → KB/MB/GB', () {
      expect(_cat(512).sizeLabel, '512 B');
      expect(_cat(1536).sizeLabel, '1.5 KB');
      expect(_cat(24 * 1024 * 1024).sizeLabel, '24 MB');
      expect(_cat(3 * 1024 * 1024 * 1024).sizeLabel, '3.0 GB');
    });
  });

  test('scanDownloads lists cache subdirs with size; clearDownloads frees them',
      () async {
    final root = Directory.systemTemp.createTempSync('dl_mgr');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    // simulate two caches: models (24 KB) + soundfonts (100 KB)
    File('${root.path}/models/m.bin')
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(24 * 1024, 0));
    File('${root.path}/soundfonts/f.sf2')
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(100 * 1024, 0));

    final cats = await scanDownloads(rootOverride: root.path);
    expect(cats, hasLength(2));
    // largest first
    expect(cats.first.id, 'soundfonts');
    expect(cats.first.bytes, 100 * 1024);
    expect(cats.first.label, 'SoundFonts'); // friendly label
    final models = cats.firstWhere((c) => c.id == 'models');
    expect(models.items, 1);

    // remove the soundfonts cache → it's gone, models remain
    await clearDownloads(cats.first.path);
    final after = await scanDownloads(rootOverride: root.path);
    expect(after.map((c) => c.id), ['models']);
  });
}
