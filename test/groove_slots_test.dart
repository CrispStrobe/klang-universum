// Groove save-slots service — persistence over a mocked SharedPreferences.

import 'package:comet_beat/features/games/composition/groove_slots.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<GrooveSlotsService> _service([
  Map<String, Object> seed = const {},
]) async {
  SharedPreferences.setMockInitialValues(seed);
  return GrooveSlotsService(await SharedPreferences.getInstance());
}

void main() {
  test('empty by default', () async {
    final s = await _service();
    expect(s.list(), isEmpty);
  });

  test('save then list, newest first', () async {
    final s = await _service();
    await s.save('First', 'KU1.aaa');
    await s.save('Second', 'KU1.bbb');
    final slots = s.list();
    expect(slots.map((e) => e.name), ['Second', 'First']);
    expect(slots.first.token, 'KU1.bbb');
  });

  test('saving an existing name replaces it and moves it to the front',
      () async {
    final s = await _service();
    await s.save('Mine', 'KU1.old');
    await s.save('Other', 'KU1.x');
    await s.save('Mine', 'KU1.new');
    final slots = s.list();
    expect(slots.map((e) => e.name), ['Mine', 'Other']);
    expect(slots.first.token, 'KU1.new');
  });

  test('blank names are ignored; delete removes', () async {
    final s = await _service();
    await s.save('   ', 'KU1.zzz');
    expect(s.list(), isEmpty);
    await s.save('Keep', 'KU1.k');
    await s.delete('Keep');
    expect(s.list(), isEmpty);
  });

  test('persists across service instances', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await GrooveSlotsService(prefs).save('Band', 'KU1.band');
    expect(GrooveSlotsService(prefs).list().single.name, 'Band');
  });

  test('a corrupt blob reads as empty, never throws', () async {
    final s = await _service({'loop_mixer_slots': 'not json'});
    expect(s.list(), isEmpty);
  });
}
