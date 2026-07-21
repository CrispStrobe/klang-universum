// Cross-tool fret-assignment bench harness (not a real test — a runner).
// Reads the shared columns.json the benchmark's MIDI extractor produces, runs
// arrangeTab over it at every cost config in a sweep, and writes frettings in
// the canonical numbering (index 0 = high E, already our Tuning's order).
//
// Skipped unless BENCH_IN/BENCH_OUT are set, so it stays inert in CI:
//   flutter test test/bench_arrange_test.dart \
//     --dart-define=BENCH_IN=/abs/columns.json \
//     --dart-define=BENCH_OUT=/abs/out_dir
//
// Emits <BENCH_OUT>/cb_m<move>_s<span>_h<height>.json per config (weights in
// hundredths), so one run covers the whole grid instead of one process launch
// per point.

// Limits are passed explicitly even when they equal the library defaults, so
// the sweep can override any of them from the command line.
// ignore_for_file: avoid_redundant_argument_values

import 'dart:convert';
import 'dart:io';

import 'package:comet_beat/features/games/composition/tab_arranger.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart' show Tuning;
import 'package:flutter_test/flutter_test.dart';

const _in = String.fromEnvironment('BENCH_IN');
const _outDir = String.fromEnvironment('BENCH_OUT');

/// Weights in hundredths, so they stay integers.
const _moves = [100];
const _spans = [30, 60, 100];
const _heights = [0, 5, 10, 20, 30, 40, 50, 60, 80];

/// 15 matches the cross-tool comparison; the shipped GP path (gpFretPlanFor)
/// arranges at 24, so conclusions must be checked at both.
const _maxFret = int.fromEnvironment('BENCH_MAXFRET', defaultValue: 15);

/// 0 = no hard span cap (historical behaviour); >0 caps a column's stretch.
const _maxSpan = int.fromEnvironment('BENCH_MAXSPAN', defaultValue: 0);

void main() {
  test('bench: arrangeTab cost sweep over shared columns', () {
    if (_in.isEmpty || _outDir.isEmpty) {
      markTestSkipped('BENCH_IN/BENCH_OUT not set');
      return;
    }
    final pieces = jsonDecode(File(_in).readAsStringSync()) as List;
    Directory(_outDir).createSync(recursive: true);

    final columnsBySource = <String, List<List<int>>>{
      for (final p in pieces.cast<Map<String, dynamic>>())
        p['source'] as String: [
          for (final c in p['columns'] as List) (c as List).cast<int>(),
        ],
    };

    var configs = 0;
    for (final m in _moves) {
      for (final s in _spans) {
        for (final h in _heights) {
          final cost = TabArrangeCost(
            move: m / 100,
            span: s / 100,
            height: h / 100,
          );
          final result = <String, List<Map<String, int>>>{};
          for (final entry in columnsBySource.entries) {
            // maxFret: 15 matches the cross-tool comparison, 24 the GP path.
            final arranged = arrangeTab(
              entry.value,
              Tuning.standardGuitar,
              maxFret: _maxFret,
              maxSpan: _maxSpan > 0 ? _maxSpan : null,
              cost: cost,
            );
            result[entry.key] = [
              for (final f in arranged)
                {for (final e in f.entries) e.key.toString(): e.value},
            ];
          }
          File(
            '$_outDir/cb_m${m}_s${s}_h$h.json',
          ).writeAsStringSync(jsonEncode(result));
          configs++;
        }
      }
    }
    // ignore: avoid_print
    print('cometbeat: ${columnsBySource.length} pieces × $configs configs');
  });
}
