// lib/features/games/composition/form_analysis_view.dart
//
// An AnaVis-style FORM-ANALYSIS view: a non-quiz teaching surface that shows a
// piece's form as a colour-coded section timeline (same letter → same colour)
// you can PLAY section by section. Tap a block to hear that section; "play the
// whole piece" hears them in order. It's the read/listen counterpart to the
// "Label the Form" game (which quizzes the same shape) and the AnaVis idea the
// curriculum flags for the form concepts — so it doubles as the textbook's
// lesson content for `musical_form` / `song_form` (see textbook_screen.dart).
//
// The example pieces are OUR OWN short motif renditions (abstract A/B/C/D
// sections, like the game's), so there is no melody-licensing risk; the caption
// names the everyday form (ternary / rondo / verse-chorus / AABA).

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/games/composition/form_timeline.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// A distinct, memorable motif per section letter (mirrors the game's set, so
/// the aural language is consistent across the analysis view and the quiz).
const _motifs = <String, List<int>>{
  'A': [60, 64, 67, 72], // rising arpeggio
  'B': [71, 69, 67, 65], // falling line
  'C': [60, 62, 64, 65], // stepwise up
  'D': [67, 65, 64, 60], // stepwise down
};

const _noteMs = 320;

/// One worked example: an ordered list of section letters + a localized title
/// (the form's everyday name) and a one-line caption.
class FormExample {
  const FormExample({
    required this.title,
    required this.caption,
    required this.pattern,
  });

  /// Localized heading (e.g. "Ternary form (A–B–A)").
  final String Function(AppLocalizations) title;

  /// Localized one-line explanation of the shape.
  final String Function(AppLocalizations) caption;

  /// The section letters in order, e.g. ['A', 'B', 'A'].
  final List<String> pattern;

  /// The (midi, ms) notes of one section.
  List<(int, int)> sectionPhrase(int i) =>
      [for (final m in _motifs[pattern[i]]!) (m, _noteMs)];

  /// The whole piece, section after section.
  List<(int, int)> get wholePhrase =>
      [for (var i = 0; i < pattern.length; i++) ...sectionPhrase(i)];
}

/// A single example rendered as a coloured, tappable timeline with a play row.
class FormAnalysisView extends StatefulWidget {
  const FormAnalysisView({super.key, required this.example});

  final FormExample example;

  @override
  State<FormAnalysisView> createState() => _FormAnalysisViewState();
}

class _FormAnalysisViewState extends State<FormAnalysisView> {
  int? _playing; // index of the section highlighted right now

  void _playSection(int i) {
    setState(() => _playing = i);
    context.read<AudioService>().playSequence(widget.example.sectionPhrase(i));
  }

  void _playWhole() {
    setState(() => _playing = null);
    context.read<AudioService>().playSequence(widget.example.wholePhrase);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final sections = [
      for (var i = 0; i < widget.example.pattern.length; i++)
        FormSection(widget.example.pattern[i], highlighted: _playing == i),
    ];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.example.title(l10n),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              widget.example.caption(l10n),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            FormTimeline(sections: sections, onTapSection: _playSection),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _playWhole,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.formAnalysisPlayWhole),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    l10n.formAnalysisHint,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The worked examples for each form concept id (empty → no "See the form"
/// button on that concept's textbook tile).
const Map<String, List<FormExample>> kFormExamples = {
  'musical_form': [
    FormExample(
      title: _ternaryTitle,
      caption: _ternaryCaption,
      pattern: ['A', 'B', 'A'],
    ),
    FormExample(
      title: _rondoTitle,
      caption: _rondoCaption,
      pattern: ['A', 'B', 'A', 'C', 'A'],
    ),
  ],
  'song_form': [
    FormExample(
      title: _verseChorusTitle,
      caption: _verseChorusCaption,
      pattern: ['A', 'B', 'A', 'B'],
    ),
    FormExample(
      title: _aabaTitle,
      caption: _aabaCaption,
      pattern: ['A', 'A', 'B', 'A'],
    ),
  ],
};

// Const tear-offs (a const map can't hold closures directly).
String _ternaryTitle(AppLocalizations l) => l.formExampleTernary;
String _ternaryCaption(AppLocalizations l) => l.formExampleTernaryCaption;
String _rondoTitle(AppLocalizations l) => l.formExampleRondo;
String _rondoCaption(AppLocalizations l) => l.formExampleRondoCaption;
String _verseChorusTitle(AppLocalizations l) => l.formExampleVerseChorus;
String _verseChorusCaption(AppLocalizations l) =>
    l.formExampleVerseChorusCaption;
String _aabaTitle(AppLocalizations l) => l.formExampleAaba;
String _aabaCaption(AppLocalizations l) => l.formExampleAabaCaption;

/// A small screen showing all the worked form examples for one concept.
class FormAnalysisScreen extends StatelessWidget {
  const FormAnalysisScreen({super.key, required this.examples});

  final List<FormExample> examples;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.formAnalysisTitle)),
      body: ListView(
        children: [
          for (final e in examples) FormAnalysisView(example: e),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
