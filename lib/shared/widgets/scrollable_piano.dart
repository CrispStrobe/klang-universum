// lib/shared/widgets/scrollable_piano.dart
//
// The app's ONE compact, sweepable on-screen piano — a horizontally-scrollable
// multi-octave [PianoKeyboard] with fixed-width keys, letter+octave labels, and
// per-key highlight (e.g. the notes currently sounding). The Composition
// Workshop, the Tracker, and the Live Looper all want the same keyboard; this
// is it, so they stop copy-pasting the scroll/size wrapper.
//
// It fills a fixed height and scrolls horizontally, so it drops into any column
// (including a vertically-scrolling page — the axes don't fight).

import 'package:comet_beat/shared/widgets/piano_keyboard.dart';
import 'package:flutter/material.dart';

class ScrollablePiano extends StatefulWidget {
  const ScrollablePiano({
    super.key,
    this.startMidi = 24, // C1
    this.whiteKeyCount = 42, // C1..~A6 — the full comfortable range
    this.keyWidth = 34,
    this.height = 88,
    this.initialMidi = 60, // scroll so C4 is in view on open
    this.onKeyTap,
    this.keyColors = const {},
    this.keyHints = const {},
    this.showLabels = true,
    this.showOctaveNumbers = true,
  }) : assert(startMidi % 12 == 0, 'startMidi must be a C');

  /// MIDI of the leftmost key (a C).
  final int startMidi;

  /// Total white keys across the whole (scrollable) range.
  final int whiteKeyCount;

  /// Width of each white key in logical pixels (compact by default).
  final double keyWidth;

  /// Fixed keyboard height.
  final double height;

  /// The keyboard scrolls so this note is near the left on first layout.
  final int initialMidi;

  final void Function(int midi)? onKeyTap;

  /// Per-key highlight fills, by MIDI — e.g. the notes currently sounding.
  final Map<int, Color> keyColors;

  /// Optional small hint drawn on a key (by MIDI), e.g. a computer-key letter.
  final Map<int, String> keyHints;

  final bool showLabels;
  final bool showOctaveNumbers;

  @override
  State<ScrollablePiano> createState() => _ScrollablePianoState();
}

class _ScrollablePianoState extends State<ScrollablePiano> {
  late final ScrollController _scroll =
      ScrollController(initialScrollOffset: _offsetFor(widget.initialMidi));

  /// Left scroll offset that brings [midi] into view (with a little lead-in).
  double _offsetFor(int midi) {
    // White keys per octave = 7; approximate the white index of [midi].
    final whiteIndex = ((midi - widget.startMidi) / 12) * 7;
    return (whiteIndex * widget.keyWidth - widget.keyWidth).clamp(
      0.0,
      double.infinity,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: widget.whiteKeyCount * widget.keyWidth,
            child: PianoKeyboard(
              startMidi: widget.startMidi,
              whiteKeyCount: widget.whiteKeyCount,
              onKeyTap: widget.onKeyTap,
              keyColors: widget.keyColors,
              keyHints: widget.keyHints,
              showLabels: widget.showLabels,
              showOctaveNumbers: widget.showOctaveNumbers,
            ),
          ),
        ),
      ),
    );
  }
}
