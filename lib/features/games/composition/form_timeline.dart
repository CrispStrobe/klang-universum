// lib/features/games/composition/form_timeline.dart
//
// A small AnaVis-style form timeline: a horizontal row of coloured, labelled
// blocks, one per section of a piece. Same letter → same colour, so the shape of
// the music (ABA, AABA, a rondo…) is visible at a glance. Reused by the "Label
// the Form" game and available for a future score-aligned analysis view.

import 'package:flutter/material.dart';

/// One coloured, labelled section on the timeline.
class FormSection {
  const FormSection(this.label, {this.highlighted = false});

  /// The section letter (A, B, C, …).
  final String label;

  /// Draw a ring around it (e.g. the section currently playing).
  final bool highlighted;
}

/// A stable colour per section letter, so A is always the same hue.
Color formColorFor(String label, ColorScheme scheme) {
  const palette = [
    Color(0xFF4E79A7), // A — blue
    Color(0xFFF28E2B), // B — orange
    Color(0xFF59A14F), // C — green
    Color(0xFFE15759), // D — red
    Color(0xFFB07AA1), // E — purple
  ];
  final i = label.isEmpty ? 0 : (label.codeUnitAt(0) - 'A'.codeUnitAt(0));
  return palette[i.clamp(0, palette.length - 1)];
}

/// A row of section blocks. Equal width by default; the shape reads left→right.
/// With [showLabels] off, only the colours show — the learner reads the repeat
/// pattern (same colour = same section) and works out the letters themselves.
class FormTimeline extends StatelessWidget {
  const FormTimeline({
    super.key,
    required this.sections,
    this.height = 64,
    this.showLabels = true,
    this.onTapSection,
  });

  final List<FormSection> sections;
  final double height;
  final bool showLabels;

  /// When set, each block is tappable (its index is passed back) — used by the
  /// AnaVis-style analysis view to hear one section. Null (the game's use) keeps
  /// the blocks inert.
  final void Function(int index)? onTapSection;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (var i = 0; i < sections.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _Block(
                  color: formColorFor(sections[i].label, scheme),
                  outline: sections[i].highlighted ? scheme.onSurface : null,
                  label: showLabels ? sections[i].label : '',
                  onTap: onTapSection == null ? null : () => onTapSection!(i),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.color,
    required this.label,
    this.outline,
    this.onTap,
  });

  final Color color;
  final String label;
  final Color? outline;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final block = DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        border: outline != null ? Border.all(color: outline!, width: 3) : null,
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 26,
          ),
        ),
      ),
    );
    if (onTap == null) return block;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: block,
      ),
    );
  }
}
