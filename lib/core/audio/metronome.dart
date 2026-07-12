// lib/core/audio/metronome.dart
//
// Detects when the play-along clock crosses an integer beat, so the UI can
// sound a count-in click. Pure Dart, testable. We click only through the
// count-in (up to and including the downbeat) and then go silent, so the
// metronome never plays over the notes the mic is scoring.

/// Emits a click on each newly-crossed integer beat, up to [throughBeat].
class CountInClicker {
  CountInClicker({this.throughBeat = 0});

  /// Click on integer beats ≤ floor(throughBeat). 0 = count-in + the downbeat.
  final double throughBeat;

  int? _last;

  /// Feed the current beat (negative during the count-in). Returns whether a
  /// click should sound this frame and whether it is an accent (the downbeat
  /// and every 4th beat).
  ({bool click, bool accent}) update(double beat) {
    final b = beat.floor();
    final crossed = _last == null || b > _last!;
    _last = b;
    if (crossed && b <= throughBeat.floor()) {
      return (click: true, accent: b % 4 == 0);
    }
    return (click: false, accent: false);
  }

  void reset() => _last = null;
}
