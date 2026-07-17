// lib/core/audio/loop_reference.dart
//
// The AEC reference-alignment core (Loop Mixer jam grading, docs/
// LOOP_MIXER_FOLLOWUPS_HANDOVER.md §B, slice B1). In Tier-3b jam mode the
// native full-duplex engine PLAYS the reference we hand it AND cancels it out
// of the mic, so the reference IS the audible groove. This class turns the
// loop's one PCM16 buffer into the stream of windows to push — walking the
// loop, wrapping the seam, and adopting a swapped-in loop (fill in/out, a
// variant/level change, an infinite-mode variation) at the seam so the swap
// lands on the downbeat, exactly like the audible LoopPlayerService swaps at
// position 0.
//
// Pure and Flutter-free on purpose: the screen drives it from a periodic
// timer, but all the seam/wrap/swap arithmetic lives here so it can be
// unit-tested against tiny synthetic loops with no audio hardware. Samples are
// mono PCM16 (little-endian, 2 bytes each) throughout — the shape
// MicrophonePitchService.pushReference and the plugin already speak.

import 'dart:typed_data';

/// Yields real-time-paced reference windows over a looping PCM16 buffer,
/// handling the loop seam and phase-preserving swaps.
class LoopReferenceScheduler {
  /// Wraps [loopPcm16] (mono PCM16, non-empty, an even number of bytes).
  LoopReferenceScheduler(Uint8List loopPcm16)
      : assert(loopPcm16.isNotEmpty, 'reference loop must be non-empty'),
        assert(loopPcm16.length.isEven, 'PCM16 has an even byte length'),
        _loop = loopPcm16;

  Uint8List _loop;

  /// A loop queued by [swap], adopted at the next seam wrap (never mid-loop).
  Uint8List? _pending;

  /// Read position within [_loop], in SAMPLES (not bytes).
  int _cursor = 0;

  /// Samples in the current loop.
  int get lengthSamples => _loop.length ~/ 2;

  /// The current read position, in samples (0 ≤ cursor < [lengthSamples]).
  int get cursorSample => _cursor;

  /// True while a [swap] is waiting for the seam.
  bool get hasPendingSwap => _pending != null;

  /// Queue [loopPcm16] to replace the current loop at the next seam wrap. Until
  /// then the current loop keeps feeding, so the swap lands on the downbeat
  /// where the kick masks it — the same discipline as the audible player. A
  /// second swap before the seam supersedes the first (only the latest matters,
  /// matching the engine's cached-render identity swap). The new loop may be a
  /// different length (a tempo/bar change); it simply starts from its own
  /// sample 0 at the seam.
  void swap(Uint8List loopPcm16) {
    assert(loopPcm16.isNotEmpty && loopPcm16.length.isEven);
    _pending = loopPcm16;
  }

  /// The next [samples] mono PCM16 samples from the cursor as a fresh
  /// little-endian byte buffer, wrapping the loop seam (and adopting a pending
  /// [swap] at each wrap) as many times as needed. Advances the cursor.
  Uint8List nextWindow(int samples) {
    assert(samples >= 0);
    final out = Uint8List(samples * 2);
    var written = 0; // bytes written into `out`
    while (written < out.length) {
      final fromByte = _cursor * 2;
      final avail = _loop.length - fromByte; // bytes left in this loop
      final want = out.length - written;
      final take = want < avail ? want : avail;
      out.setRange(
        written,
        written + take,
        Uint8List.sublistView(_loop, fromByte, fromByte + take),
      );
      written += take;
      _cursor += take ~/ 2;
      if (_cursor * 2 >= _loop.length) {
        // Seam: wrap to the top and adopt any queued loop on the downbeat.
        _cursor = 0;
        final pending = _pending;
        if (pending != null) {
          _loop = pending;
          _pending = null;
        }
      }
    }
    return out;
  }

  /// The bar index the cursor currently sits in, given [samplesPerBar] (from
  /// the musical clock) — what the jam grader colours a note against.
  int barAt(int samplesPerBar) =>
      samplesPerBar <= 0 ? 0 : _cursor ~/ samplesPerBar;
}
