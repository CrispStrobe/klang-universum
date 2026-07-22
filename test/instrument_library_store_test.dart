// The persistent "My Instruments" library store. The save format is the engine
// instrument codec, so these lock: an instrument round-trips through the store
// and rebuilds to a PLAYABLE instrument; overwrite/delete work; malformed input
// is ignored (never throws).

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_instrument_codec.dart';
import 'package:comet_beat/features/sound_lab/instrument_library_store.dart';
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

SampleInstrument _voice(String id) {
  final pcm = Float64List(2048);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = 0.4 * math.sin(2 * math.pi * 220 * i / 44100);
  }
  return SampleInstrument(id, pcm);
}

SavedInstrument _saved(String name) => SavedInstrument(
      name: name,
      json: instrumentToJsonString(_voice(name)),
      source: 'Voice Lab',
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('encode/decode round-trips a saved instrument', () {
    final items = [_saved('bell'), _saved('pluck')];
    final back = decodeInstruments(encodeInstruments(items));
    expect(back.map((s) => s.name), ['bell', 'pluck']);
    expect(back.first.source, 'Voice Lab');
    expect(back.first.kind, 'sample');
    expect(back.first.isReference, isFalse);
  });

  test('a saved instrument rebuilds to a playable instrument', () {
    final saved = _saved('myvoice');
    final inst = saved.instrument;
    expect(inst, isNotNull);
    // it renders a note (non-silent) — proof the whole codec round-tripped
    const timing = TrackerTiming(rows: 4);
    final pcm = inst!.renderChannel(const [TrackerCell(midi: 60)], timing);
    var peak = 0.0;
    for (final s in pcm) {
      if (s.abs() > peak) peak = s.abs();
    }
    expect(peak, greaterThan(0.01));
  });

  test('save persists; overwrite by name; delete removes', () async {
    final store = InstrumentLibraryStore();
    await store.save(_saved('one'));
    await store.save(_saved('two'));
    expect((await store.load()).map((s) => s.name), ['one', 'two']);

    // same name overwrites (not a duplicate)
    await store.save(SavedInstrument(name: 'one', json: _saved('one').json));
    expect((await store.load()).where((s) => s.name == 'one'), hasLength(1));

    await store.delete('one');
    expect((await store.load()).map((s) => s.name), ['two']);
  });

  test('malformed / blank input decodes to empty, never throws', () {
    expect(decodeInstruments(null), isEmpty);
    expect(decodeInstruments(''), isEmpty);
    expect(decodeInstruments('not json'), isEmpty);
    expect(decodeInstruments('{"not":"a list"}'), isEmpty);
    // a list with a junk entry keeps the good ones
    final good = jsonEncode(_saved('ok').toJson());
    expect(
      decodeInstruments('[{"bad":1}, $good]').map((s) => s.name),
      ['ok'],
    );
  });

  test('a reference-type instrument is flagged and not resolved inline', () {
    // A soundfont_ref keeps only a pointer; instrument (sync) must be null.
    const ref = SavedInstrument(
      name: 'GM Piano',
      json: '{"type":"soundfont_ref","path":"x.sf2","bank":0,"program":0}',
    );
    expect(ref.kind, 'soundfont_ref');
    expect(ref.isReference, isTrue);
    expect(ref.instrument, isNull);
  });

  test('category maps each kind to its rubric', () {
    String cat(String type) =>
        SavedInstrument(name: 'x', json: '{"type":"$type"}').category;
    expect(cat('sample'), 'Samples');
    expect(cat('sfxr'), 'FX');
    expect(cat('soundfont_ref'), 'SoundFonts');
    expect(cat('percussion'), 'Drums');
    expect(cat('additive'), 'Instruments');
    expect(cat('fm'), 'Instruments');
    expect(kLibraryCategories, contains('Samples'));
  });

  test('fromSampleClip folds a clip in as a playable sample, keeping licence',
      () {
    final pcm = Float64List(1024);
    for (var i = 0; i < pcm.length; i++) {
      pcm[i] = 0.3 * math.sin(2 * math.pi * 330 * i / 44100);
    }
    final s = SavedInstrument.fromSampleClip(SampleClip(
      name: 'Guitar hit',
      sampleRate: 44100,
      pcm: pcm,
      source: 'Freepats',
      license: 'CC BY 4.0',
      sourceUrl: 'https://example/x',
    ));
    expect(s.kind, 'sample');
    expect(s.category, 'Samples');
    expect(s.license, 'CC BY 4.0');
    expect(s.sourceUrl, 'https://example/x');
    expect(s.needsAttribution, isTrue); // CC BY obliges credit
    expect(s.instrument, isA<SampleInstrument>()); // rebuilds and plays
    // survives the store's own JSON round-trip
    final back = decodeInstruments(encodeInstruments([s])).single;
    expect(back.license, 'CC BY 4.0');
    expect(back.needsAttribution, isTrue);
  });

  test('CC0 samples need no attribution', () {
    const s = SavedInstrument(
      name: 'x',
      json: '{"type":"sample"}',
      license: 'CC0',
    );
    expect(s.needsAttribution, isFalse);
  });

  test('legacy My Samples fold into the unified store once, then are skipped',
      () async {
    final pcm = Float64List(512)..[0] = 0.5;
    // Seed the OLD samples key, empty instruments.
    SharedPreferences.setMockInitialValues({
      'sound_lab_samples': encodeClips([
        SampleClip(name: 'clap', sampleRate: 44100, pcm: pcm, license: 'CC0'),
      ]),
    });
    final store = InstrumentLibraryStore();
    final first = await store.load();
    expect(first.map((s) => s.name), contains('clap'));
    expect(first.firstWhere((s) => s.name == 'clap').category, 'Samples');
    // Migration flag set → a second load doesn't re-add (idempotent).
    final again = await store.load();
    expect(again.where((s) => s.name == 'clap'), hasLength(1));
  });
}
