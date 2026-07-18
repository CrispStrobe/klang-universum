// Looper core (roadmap item 4): seamless loop-length quantise, quantised
// punch-in/out, and the undo/redo overdub stack. Pure, headless.

import 'package:comet_beat/core/audio/loop_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const barMs = 2000.0; // one 4/4 bar at 120 bpm

  group('quantizeLoopBars (seamless loop lengths)', () {
    test('rounds a slightly-off take to a whole number of bars', () {
      expect(quantizeLoopBars(4000, barMs), 2); // exactly 2 bars
      expect(quantizeLoopBars(4120, barMs), 2); // a hair long → still 2
      expect(quantizeLoopBars(3880, barMs), 2); // a hair short → still 2
      expect(quantizeLoopBars(5200, barMs), 3); // closer to 3
    });

    test('never below minBars, and degenerate bar length is safe', () {
      expect(quantizeLoopBars(100, barMs), 1); // rounds to 0 → floored at 1
      expect(quantizeLoopBars(9000, barMs, minBars: 4), 5);
      expect(quantizeLoopBars(100, barMs, minBars: 2), 2);
      expect(quantizeLoopBars(4000, 0), 1); // barMs <= 0 → minBars
    });
  });

  group('snapPunch (quantised punch-in/out)', () {
    test('snaps a raw window to bar boundaries', () {
      // In just after the downbeat of bar 1, out just before the end of bar 2.
      expect(snapPunch(2100, 5900, barMs), (1, 3));
      // Dead-on boundaries pass through.
      expect(snapPunch(0, 4000, barMs), (0, 2));
    });

    test('guarantees at least minBars of length', () {
      // A blip within one bar still yields a one-bar loop.
      expect(snapPunch(100, 300, barMs), (0, 1));
      expect(snapPunch(2100, 2200, barMs, minBars: 2), (1, 3));
    });

    test('degenerate bar length is safe', () {
      expect(snapPunch(0, 4000, 0), (0, 1));
    });
  });

  group('LoopStack (overdub layers + undo/redo + mute)', () {
    test('layers, undo and redo behave like an editor', () {
      final s = LoopStack<String>();
      expect(s.isEmpty, isTrue);
      expect(s.canUndo, isFalse);

      s.add('kick');
      s.add('snare');
      expect(s.layers, ['kick', 'snare']);
      expect(s.length, 2);

      s.undo();
      expect(s.layers, ['kick']);
      expect(s.canRedo, isTrue);

      s.redo();
      expect(s.layers, ['kick', 'snare']);
      expect(s.canRedo, isFalse);
    });

    test('adding a layer clears the redo stack', () {
      final s = LoopStack<String>()
        ..add('a')
        ..add('b');
      s.undo(); // b is now redoable
      s.add('c'); // a fresh overdub discards the redo branch
      expect(s.canRedo, isFalse);
      expect(s.layers, ['a', 'c']);
    });

    test('muted layers stay in the stack but drop out of activeLayers', () {
      final s = LoopStack<String>()
        ..add('kick')
        ..add('hat');
      s.toggleMute(1);
      expect(s.isMuted(1), isTrue);
      expect(s.layers, ['kick', 'hat']); // still there
      expect(s.activeLayers, ['kick']); // but not summed

      s.toggleMute(1);
      expect(s.activeLayers, ['kick', 'hat']);
    });

    test('clear drops everything including the redo branch', () {
      final s = LoopStack<int>()
        ..add(1)
        ..add(2);
      s.undo();
      s.clear();
      expect(s.isEmpty, isTrue);
      expect(s.canRedo, isFalse);
    });
  });
}
