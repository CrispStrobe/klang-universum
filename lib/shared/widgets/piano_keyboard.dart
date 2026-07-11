// lib/shared/widgets/piano_keyboard.dart
//
// A tappable piano keyboard, drawn with plain widgets: a row of white keys
// with the black keys overlaid. Reusable across the keyboard games — the
// games decide what a tap means and what sound it makes.

// Material's Stepper also exports a `Step`; partitura's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:klang_universum/features/games/note_reading/note_names.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:partitura/partitura.dart' show Step;

class PianoKeyboard extends StatelessWidget {
  /// MIDI number of the leftmost key; must be a C (e.g. 60 = C4).
  final int startMidi;

  /// Number of white keys (12 = an octave and a fifth).
  final int whiteKeyCount;

  final void Function(int midi)? onKeyTap;

  /// Per-key highlight fills, by MIDI number.
  final Map<int, Color> keyColors;

  /// Letter labels on the white keys (localized; German B = H).
  final bool showLabels;

  const PianoKeyboard({
    super.key,
    this.startMidi = 60,
    this.whiteKeyCount = 12,
    this.onKeyTap,
    this.keyColors = const {},
    this.showLabels = false,
  }) : assert(startMidi % 12 == 0, 'startMidi must be a C');

  static const _whiteOffsets = [0, 2, 4, 5, 7, 9, 11];
  static const _whiteSteps = [
    Step.c,
    Step.d,
    Step.e,
    Step.f,
    Step.g,
    Step.a,
    Step.b,
  ];

  /// MIDI number of the i-th white key.
  int whiteMidi(int i) => startMidi + 12 * (i ~/ 7) + _whiteOffsets[i % 7];

  /// Whether a black key sits between white keys [i] and i+1.
  bool hasBlackAfter(int i) => const {0, 1, 3, 4, 5}.contains(i % 7);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final keyWidth = constraints.maxWidth / whiteKeyCount;
        final blackWidth = keyWidth * 0.62;
        final height = constraints.maxHeight;

        return Stack(
          children: [
            Row(
              children: [
                for (var i = 0; i < whiteKeyCount; i++)
                  Expanded(
                    child: GestureDetector(
                      onTap: onKeyTap == null
                          ? null
                          : () => onKeyTap!(whiteMidi(i)),
                      child: Container(
                        decoration: BoxDecoration(
                          color: keyColors[whiteMidi(i)] ?? Colors.white,
                          border: Border.all(color: Colors.black87),
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(6),
                          ),
                        ),
                        alignment: Alignment.bottomCenter,
                        padding: const EdgeInsets.only(bottom: 8),
                        child: showLabels
                            ? Text(
                                noteName(l10n, _whiteSteps[i % 7]),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black54,
                                    ),
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            for (var i = 0; i < whiteKeyCount - 1; i++)
              if (hasBlackAfter(i))
                Positioned(
                  left: (i + 1) * keyWidth - blackWidth / 2,
                  top: 0,
                  width: blackWidth,
                  height: height * 0.58,
                  child: GestureDetector(
                    onTap: onKeyTap == null
                        ? null
                        : () => onKeyTap!(whiteMidi(i) + 1),
                    child: Container(
                      decoration: BoxDecoration(
                        color: keyColors[whiteMidi(i) + 1] ?? Colors.black87,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}
