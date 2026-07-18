// lib/core/audio/loop_record.dart
//
// Looper primitives (roadmap item 4, "a much better looper") — the pure core:
//   • quantizeLoopBars — snap a recorded phrase to a whole number of bars, so
//     layered loops line up seamlessly (no drifting tail);
//   • snapPunch — snap a raw record in/out window to bar boundaries (quantised
//     punch-in / punch-out), so an overdub aligns to the loop;
//   • LoopStack<T> — an ordered overdub layer stack with undo/redo + per-layer
//     mute (tighter overdub/undo + live layering).
// Pure Dart, headless-testable; a Looper surface (or the DrumKit / Loop Mixer)
// drives these.

/// Snap a recorded phrase of [recordedMs] to a whole number of bars (each
/// [barMs] long), floored at [minBars]. So a take a hair over two bars becomes
/// exactly two — the seam is clean and layers stay in phase. A non-positive
/// [barMs] falls back to [minBars].
int quantizeLoopBars(double recordedMs, double barMs, {int minBars = 1}) {
  if (barMs <= 0) return minBars;
  final bars = (recordedMs / barMs).round();
  return bars < minBars ? minBars : bars;
}

/// Snap a raw record window [rawStartMs]..[rawStopMs] to bar boundaries: the
/// punch-in lands on a downbeat, the punch-out on a barline. Returns
/// `(startBar, endBar)` as bar indices (endBar EXCLUSIVE), guaranteeing at least
/// [minBars] of length. A non-positive [barMs] yields `(0, minBars)`.
(int startBar, int endBar) snapPunch(
  double rawStartMs,
  double rawStopMs,
  double barMs, {
  int minBars = 1,
}) {
  if (barMs <= 0) return (0, minBars);
  final start = (rawStartMs / barMs).round();
  var end = (rawStopMs / barMs).round();
  if (end < start + minBars) end = start + minBars;
  return (start, end);
}

class _Layer<T> {
  _Layer(this.data);
  final T data;
  bool muted = false;
}

/// An ordered stack of overdub layers of type [T], with standard editor
/// undo/redo and per-layer mute. [add] pushes a layer and clears the redo stack;
/// [undo] pops the last layer onto the redo stack; [redo] restores it. Muted
/// layers stay in the stack (and in [layers]) but drop out of [activeLayers] —
/// the set a looper would actually sum.
class LoopStack<T> {
  final List<_Layer<T>> _layers = [];
  final List<_Layer<T>> _redo = [];

  /// Number of layers currently in the stack (muted ones included).
  int get length => _layers.length;

  /// Whether the stack has no layers.
  bool get isEmpty => _layers.isEmpty;

  /// Every layer's data, oldest first (muted included).
  List<T> get layers => [for (final l in _layers) l.data];

  /// The unmuted layers, oldest first — what a looper sums to audio.
  List<T> get activeLayers => [
        for (final l in _layers)
          if (!l.muted) l.data,
      ];

  /// Push a new overdub layer on top; this clears the redo stack.
  void add(T layer) {
    _layers.add(_Layer(layer));
    _redo.clear();
  }

  /// Whether [undo] would do anything.
  bool get canUndo => _layers.isNotEmpty;

  /// Remove the most recently added layer, keeping it for [redo].
  void undo() {
    if (_layers.isEmpty) return;
    _redo.add(_layers.removeLast());
  }

  /// Whether [redo] would do anything.
  bool get canRedo => _redo.isNotEmpty;

  /// Restore the last undone layer.
  void redo() {
    if (_redo.isEmpty) return;
    _layers.add(_redo.removeLast());
  }

  /// Whether layer [index] is muted.
  bool isMuted(int index) => _layers[index].muted;

  /// Flip layer [index]'s mute state.
  void toggleMute(int index) => _layers[index].muted = !_layers[index].muted;

  /// Drop every layer (and the redo stack).
  void clear() {
    _layers.clear();
    _redo.clear();
  }
}
