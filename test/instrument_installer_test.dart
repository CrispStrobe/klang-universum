// The batch SFZ-instrument installer: discovers the SFZ's sample refs, downloads
// the whole tree into a temp cache, and loads a playable voice. Fake HTTP + a
// real minimal WAV sample — no network. Also proves the cache is kept (a second
// install re-uses it, no re-download).

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/features/library/instrument_installer.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart'
    show pcmFloatToWav;
import 'package:flutter_test/flutter_test.dart';

const _sfz = '''
<region>
sample=samples/a.wav
pitch_keycenter=60
lokey=0 hikey=127
''';

void main() {
  test('installs an SFZ + its sample tree into the cache, loads a voice',
      () async {
    final cache = Directory.systemTemp.createTempSync('inst_install');
    addTearDown(() {
      if (cache.existsSync()) cache.deleteSync(recursive: true);
    });

    final wav = pcmFloatToWav(
      Float64List.fromList(List.generate(2048, (i) => (i % 64 - 32) / 64.0)),
      sampleRate: 22050,
    );
    var sampleFetches = 0;
    Future<Uint8List> http(Uri url) async {
      final u = url.toString();
      if (u.endsWith('.sfz')) return Uint8List.fromList(_sfz.codeUnits);
      if (u.endsWith('samples/a.wav')) {
        sampleFetches++;
        return wav;
      }
      throw Exception('404 $u');
    }

    final installed = await installSfzInstrument(
      sfzUrl: 'https://h/vcsl/MyInst.sfz',
      name: 'My Inst',
      http: http,
      cacheDirOverride: cache.path,
    );

    expect(installed, isNotNull);
    expect(installed!.fileCount, 2); // the .sfz + one sample
    expect(sampleFetches, 1);
    // the tree is cached on disk (kept)
    expect(
      File('${cache.path}/instruments/My_Inst/instrument.sfz').existsSync(),
      isTrue,
    );
    expect(
      File('${cache.path}/instruments/My_Inst/samples/a.wav').existsSync(),
      isTrue,
    );
    // it built a real voice (non-null instrument)
    expect(installed.instrument, isNotNull);

    // a second install re-uses the cache (no re-download)
    await installSfzInstrument(
      sfzUrl: 'https://h/vcsl/MyInst.sfz',
      name: 'My Inst',
      http: http,
      cacheDirOverride: cache.path,
    );
    expect(sampleFetches, 1, reason: 'cached — not fetched again');
  });

  test('instrumentInstallSupported is true on native', () {
    expect(instrumentInstallSupported, isTrue);
  });
}
