// BeatBridge — the shared groove backbone. One in-memory "current beat" that
// every mode can PUBLISH to and PULL from, so the Drum Kit, Loop Mixer, Live
// Looper and the Trackers all edit the SAME beat: change it in one, load it in
// another. The unit is the common [DrumRowsPattern] (Map<Drum, List<bool>>) that
// the Drum Kit and Loop Mixer already share, plus tempo/swing.
//
// Deliberately a plain singleton (not a provider): the modes are separate
// screens navigated one at a time, so an explicit publish/pull (a button, or an
// on-enter load) is the right model — no live cross-screen wiring needed. Screens
// that want to react while visible can listen to [beat].
//
// Pure Dart (only depends on the Drum enum) → unit-tested in
// test/beat_bridge_test.dart.

import 'package:comet_beat/core/audio/loop_engine.dart' show DrumRowsPattern;
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:flutter/foundation.dart';

/// A per-drum sound override carried with a shared beat: an instrument's
/// display [name] + its [instrumentToJsonString] payload. Kept as plain strings
/// so this core service needn't depend on the Sound-Lab feature layer — a
/// consumer rebuilds the instrument via `instrumentFromJsonString` (and the UI
/// its `SavedInstrument` from name+json).
@immutable
class SharedVoice {
  const SharedVoice(this.name, this.json);
  final String name;
  final String json;
}

/// An immutable snapshot of a shared beat: the per-drum step rows plus the
/// tempo/swing it was authored at, and optional per-drum sound overrides. Rows
/// are copied on construction so a later edit in the source mode can't mutate
/// the shared copy.
@immutable
class SharedBeat {
  SharedBeat({
    required Map<Drum, List<bool>> rows,
    required this.tempoBpm,
    this.swing = 0,
    this.source = '',
    Map<Drum, SharedVoice> voices = const {},
  })  : rows = {
          for (final e in rows.entries) e.key: List<bool>.unmodifiable(e.value),
        },
        voices = Map<Drum, SharedVoice>.unmodifiable(voices);

  /// Per-drum sound overrides (empty = every drum uses the consumer's own kit).
  /// A mode that can play arbitrary samples (the Drum Kit, the Advanced Tracker)
  /// applies these; others keep the pattern and their own drum sounds.
  final Map<Drum, SharedVoice> voices;

  /// One boolean row per drum voice (a step is a hit). Sparse is fine — an
  /// absent drum reads as all-silent.
  final Map<Drum, List<bool>> rows;
  final int tempoBpm;

  /// 0 = straight; up to ~0.6 delays every off-eighth (a swing feel).
  final double swing;

  /// A short tag for where it came from (e.g. "drumkit", "loopmixer") — purely
  /// informational, for a "loaded from …" hint.
  final String source;

  /// The step count of the longest row (0 if empty).
  int get steps => rows.values.fold(0, (m, r) => r.length > m ? r.length : m);

  bool get isEmpty => rows.values.every((r) => !r.contains(true));

  /// As a Loop Mixer [DrumRowsPattern] (the same map, ready to render).
  DrumRowsPattern toDrumPattern() => DrumRowsPattern({
        for (final e in rows.entries) e.key: [...e.value],
      });

  /// The rows re-fitted to [steps] columns: longer rows are truncated, shorter
  /// ones padded with silence, and every [Drum] is present. So a consumer on a
  /// different grid length always gets a full, correctly-sized pattern.
  Map<Drum, List<bool>> rowsFitted(int steps) => {
        for (final d in Drum.values)
          d: [
            for (var i = 0; i < steps; i++)
              (rows[d] != null && i < rows[d]!.length) ? rows[d]![i] : false,
          ],
      };
}

/// The process-wide shared beat. Publish from any mode, pull into any other.
class BeatBridge {
  BeatBridge._();
  static final BeatBridge instance = BeatBridge._();

  /// The current shared beat (null until something publishes). Listenable so a
  /// visible screen can live-react; most consumers just read it on demand.
  final ValueNotifier<SharedBeat?> beat = ValueNotifier<SharedBeat?>(null);

  SharedBeat? get current => beat.value;
  bool get hasBeat => beat.value != null && !beat.value!.isEmpty;

  void publish(SharedBeat b) => beat.value = b;

  /// Test/reset hook.
  @visibleForTesting
  void clear() => beat.value = null;
}
