// Daily practice streak in ProgressService: finishing a game marks the day; the
// streak is consecutive practice days ending today (with a one-day grace so it
// doesn't read as broken before the first session of the day).

import 'package:comet_beat/core/services/progress_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a finished game marks today and starts a streak', () async {
    var now = DateTime(2026, 1, 10);
    final p = ProgressService(now: () => now);
    await p.load();
    expect(p.currentStreak, 0);

    p.recordResult('g', score: 100, stars: 3);
    expect(p.currentStreak, 1);
    expect(p.practicedOn(DateTime(2026, 1, 10)), isTrue);

    now = DateTime(2026, 1, 11);
    p.recordResult('g', score: 100, stars: 3);
    expect(p.currentStreak, 2);
  });

  test('a skipped day breaks the streak', () async {
    var now = DateTime(2026, 1, 10);
    final p = ProgressService(now: () => now);
    await p.load();
    p.recordResult('g', score: 100, stars: 3); // 10th
    now = DateTime(2026, 1, 13); // skipped 11th, 12th
    p.recordResult('g', score: 100, stars: 3); // 13th
    expect(p.currentStreak, 1);
  });

  // Regression: the streak walked back with `subtract(Duration(days: 1))`,
  // which is 24 h of ABSOLUTE time. The day after a spring-forward DST change
  // only has 23 h, so subtracting 24 h overshoots to 23:00 of the day-before —
  // its date-key skips the intervening day and the streak breaks. The audience
  // is German (CET/CEST). (Spring-forward 2026: Sun Mar 29 02:00→03:00.) On a
  // non-DST runner both walks agree, so this passes everywhere but only catches
  // a regression where DST is observed — which is where real users are.
  test('a streak survives a spring-forward DST boundary', () async {
    var now = DateTime(2026, 3, 28);
    final p = ProgressService(now: () => now);
    await p.load();
    p.recordResult('g', score: 100, stars: 3); // Mar 28
    now = DateTime(2026, 3, 29);
    p.recordResult('g', score: 100, stars: 3); // Mar 29 (the short day)
    now = DateTime(2026, 3, 30);
    p.recordResult('g', score: 100, stars: 3); // Mar 30
    expect(p.currentStreak, 3, reason: 'DST day must not be skipped');
  });

  test('the grace day survives a spring-forward DST boundary', () async {
    var now = DateTime(2026, 3, 29); // practiced the short day
    final p = ProgressService(now: () => now);
    await p.load();
    p.recordResult('g', score: 100, stars: 3);
    now = DateTime(2026, 3, 30); // morning after, not practiced yet
    expect(
      p.currentStreak,
      1,
      reason: 'yesterday-grace must cross the DST day',
    );
  });

  test('yesterday-only still counts today (grace), two-day gap does not',
      () async {
    var now = DateTime(2026, 1, 10);
    final p = ProgressService(now: () => now);
    await p.load();
    p.recordResult('g', score: 100, stars: 3); // practiced the 10th

    now = DateTime(2026, 1, 11); // not practiced yet today
    expect(p.currentStreak, 1); // grace: yesterday counts
    now = DateTime(2026, 1, 12); // two days since practice
    expect(p.currentStreak, 0);
  });

  test('practice days persist across instances', () async {
    var now = DateTime(2026, 1, 10);
    final first = ProgressService(now: () => now);
    await first.load();
    first.recordResult('g', score: 100, stars: 3);
    now = DateTime(2026, 1, 11);
    first.recordResult('g', score: 100, stars: 3);
    await _settle();

    final second = ProgressService(now: () => DateTime(2026, 1, 11));
    await second.load();
    expect(second.currentStreak, 2);
    expect(second.practicedOn(DateTime(2026, 1, 10)), isTrue);
  });
}
