// MelodyBridge — the pitched twin of BeatBridge. One in-memory "current tune"
// that modes can PUBLISH to and PULL from, so the Loop Mixer, Live Looper and
// the Trackers can hand the SAME melody around: build it in one, load it in
// another. The unit is a bar-cycle of [PatternCell]s (the melodic pattern the
// engine already renders) plus the instrument it was voiced with and the
// tempo/key it was authored at.
//
// Like BeatBridge: a plain singleton (screens are navigated one at a time, so
// an explicit publish/pull is the right model), listenable via [melody]. Pure
// Dart (only depends on the loop-engine model) → unit-tested.

import 'package:comet_beat/core/audio/loop_engine.dart' show PatternCell;
import 'package:flutter/foundation.dart';

/// An immutable snapshot of a shared tune: the melodic cells plus the
/// instrument name it was voiced with and the tempo/key it was authored at.
class SharedMelody {
  SharedMelody({
    required List<PatternCell> cells,
    required this.tempoBpm,
    this.instrument,
    this.key = 0,
    this.source = '',
  }) : cells = List<PatternCell>.unmodifiable(cells);

  /// One bar-cycle of the melody, as the engine's own [PatternCell]s.
  final List<PatternCell> cells;

  /// The instrument the tune was voiced with (an `Instrument.name`), or null.
  final String? instrument;

  final int tempoBpm;

  /// Semitones the tune's pitches were transposed by (the authoring key).
  final int key;

  /// Which mode published it (e.g. 'loopmixer') — for a friendly note.
  final String source;

  /// True when there is no sounding note (all rests).
  bool get isEmpty => cells.every((c) => c.midis == null || c.midis!.isEmpty);

  /// The cells, ready to hand to `LoopEngine.setUserTrack`.
  List<PatternCell> toCells() => [...cells];
}

class MelodyBridge {
  MelodyBridge._();
  static final MelodyBridge instance = MelodyBridge._();

  /// The current shared tune (null until something publishes). Listenable so a
  /// visible screen can react.
  final ValueNotifier<SharedMelody?> melody =
      ValueNotifier<SharedMelody?>(null);

  SharedMelody? get current => melody.value;
  bool get hasMelody => melody.value != null && !melody.value!.isEmpty;

  void publish(SharedMelody m) => melody.value = m;

  void clear() => melody.value = null;
}
