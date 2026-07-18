import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

/// A small built-in ASCII-tab riff so the screen is never empty. Parsed with
/// [asciiTabToScore] on open.
const _demoTab = '''
e|---0-------3-----0-------|
B|-----1-------1-------1---|
G|-------0-------0-------0-|
D|-------------------------|
A|-------------------------|
E|-0-------3-------0-------|
''';

/// Tuning presets offered in the picker (label ← [Tuning.name]).
final List<Tuning> tabTuningPresets = <Tuning>[
  Tuning.standardGuitar,
  Tuning.dropDGuitar,
  Tuning.dadgadGuitar,
  Tuning.openGGuitar,
  Tuning.sevenStringGuitar,
  Tuning.eightStringGuitar,
  Tuning.standardBass,
  Tuning.fiveStringBass,
  Tuning.ukulele,
  Tuning.mandolin,
  Tuning.banjoOpenG,
];

/// Extensions the tab reader accepts. Guitar Pro (`.gp`/`.gpx`) carry real
/// tab/fret data; the rest are read as pitches and laid out on the fretboard by
/// the tab engine (lowest-fret placement).
const List<String> tabImportExtensions = <String>[
  'gp',
  'gpx',
  'musicxml',
  'xml',
  'mxl',
  'mid',
  'midi',
  'abc',
];

/// Parses an opened file into a [Score] by its extension — the tab editor's own
/// import (kept separate from the Workshop's `importScore` so this screen stays
/// self-contained). Pure given the raw [bytes], so it is unit-testable without a
/// file picker. Throws a [FormatException] on an unknown extension.
Score parseTabFile(String fileName, Uint8List bytes) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  String text() => utf8.decode(bytes);
  return switch (ext) {
    'gp' => scoreFromGpif(readGpifFromGp(bytes)),
    'gpx' => scoreFromGpif(readGpifFromGpx(bytes)),
    'musicxml' || 'xml' => scoreFromMusicXml(text()),
    'mxl' => scoreFromMusicXml(readMusicXmlFromMxl(bytes)),
    'mid' || 'midi' => scoreFromMidi(bytes),
    'abc' => scoreFromAbc(text()),
    _ => throw FormatException('Unsupported file type: .$ext'),
  };
}

/// Test seam onto [TabWorkshopScreen]'s state — lets a widget test drive
/// file-open (with injected bytes) and read what's shown without touching the
/// platform picker.
abstract class TabWorkshopTester {
  Future<void> openScoreFile({String? pickedName, Uint8List? pickedBytes});
  String? get sourceName;
  Tuning get tuning;
  int get capo;
}

/// Read-only guitar/bass **tablature** viewer — the first slice of the Tab
/// Workshop. Renders any [Score] as tab (with a synced standard staff) for a
/// chosen [Tuning] + capo, and opens Guitar Pro / MusicXML / MIDI / ABC files.
/// Editing (fret entry, techniques, export) lands in later slices; the model is
/// the same [Score] the Score Workshop and Tracker use, so it bridges both.
class TabWorkshopScreen extends StatefulWidget {
  /// Optional score to open (e.g. handed over from the Workshop). When null a
  /// built-in demo riff is shown.
  final Score? initialScore;

  const TabWorkshopScreen({super.key, this.initialScore});

  @override
  State<TabWorkshopScreen> createState() => _TabWorkshopScreenState();
}

class _TabWorkshopScreenState extends State<TabWorkshopScreen>
    implements TabWorkshopTester {
  late Score _score;
  Tuning _tuning = Tuning.standardGuitar;
  int _capo = 0;
  bool _showStandard = true;
  String? _sourceName;

  @override
  String? get sourceName => _sourceName;
  @override
  Tuning get tuning => _tuning;
  @override
  int get capo => _capo;

  @override
  void initState() {
    super.initState();
    _score = widget.initialScore ?? asciiTabToScore(_demoTab);
  }

  /// Opens a file and, on success, shows it as tab. Injects [pickedName]/
  /// [pickedBytes] in tests instead of touching the platform picker.
  @override
  Future<void> openScoreFile({
    String? pickedName,
    Uint8List? pickedBytes,
  }) async {
    String name;
    Uint8List bytes;
    if (pickedBytes != null && pickedName != null) {
      name = pickedName;
      bytes = pickedBytes;
    } else {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Scores & tabs', extensions: tabImportExtensions),
        ],
      );
      if (file == null) return;
      name = file.name;
      bytes = await file.readAsBytes();
    }
    try {
      final score = parseTabFile(name, bytes);
      if (!mounted) return;
      setState(() {
        _score = score;
        _sourceName = name;
      });
    } catch (_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.tabImportFailed)));
    }
  }

  void _loadDemo() => setState(() {
        _score = asciiTabToScore(_demoTab);
        _sourceName = null;
      });

  String _tuningLabel(Tuning t) => t.name ?? '${t.stringCount}-string';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final view = _showStandard
        ? NotationTabView(
            score: _score,
            tuning: _tuning,
            capo: _capo,
            showTuning: true,
          )
        : TabStaffView(
            score: _score,
            tuning: _tuning,
            capo: _capo,
            showTuning: true,
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(_sourceName ?? l10n.tabWorkshopTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: l10n.tabImport,
            onPressed: openScoreFile,
          ),
          IconButton(
            icon: const Icon(Icons.music_note),
            tooltip: l10n.tabDemo,
            onPressed: _loadDemo,
          ),
        ],
      ),
      body: Column(
        children: [
          _controls(l10n),
          const Divider(height: 1),
          Expanded(
            child: InteractiveViewer(
              constrained: false,
              minScale: 0.5,
              maxScale: 3,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: view,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls(AppLocalizations l10n) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(l10n.tabTuning),
          const SizedBox(width: 8),
          DropdownButton<Tuning>(
            value: _tuning,
            onChanged: (t) => setState(() => _tuning = t ?? _tuning),
            items: [
              for (final t in tabTuningPresets)
                DropdownMenuItem(value: t, child: Text(_tuningLabel(t))),
            ],
          ),
          const SizedBox(width: 20),
          Text(l10n.tabCapo),
          IconButton(
            icon: const Icon(Icons.remove),
            tooltip: l10n.tabCapo,
            onPressed: _capo > 0 ? () => setState(() => _capo--) : null,
          ),
          Text('$_capo'),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.tabCapo,
            onPressed: _capo < 12 ? () => setState(() => _capo++) : null,
          ),
          const SizedBox(width: 20),
          Text(l10n.tabShowStandard),
          Switch(
            value: _showStandard,
            onChanged: (v) => setState(() => _showStandard = v),
          ),
        ],
      ),
    );
  }
}
