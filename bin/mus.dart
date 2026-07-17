// bin/mus.dart
//
// One command over the whole headless CometBeat CLI suite — a thin dispatcher
// that forwards to the individual tools in-process (each is a plain `main` over
// the Flutter-free lib/core/audio). Flutter-free, runs under plain `dart run`.
//
//   dart run bin/mus.dart <command> [args…]
//
//   listen   mic / WAV → live pitch & chord detection   (bin/listen.dart)
//   info     sniff + dump any module (.mod/.s3m/.xm/.it) (bin/modinfo.dart)
//   conv     convert modules + extract samples to WAV    (bin/modconv.dart)
//   render   a Loop Mixer groove → WAV                    (bin/render.dart)
//   midi     a module's melody → Standard MIDI File       (bin/notaconv.dart)
//   fx       apply a crisp_dsp effect to a WAV            (bin/fxproc.dart)
//
//   e.g.  dart run bin/mus.dart info song.it
//         dart run bin/mus.dart fx in.wav out.wav --effect reverb
//
// Each subcommand's own `--help`/usage is printed when its args are wrong.

import 'dart:io';

import 'fxproc.dart' as fxproc;
import 'listen.dart' as listen;
import 'modconv.dart' as modconv;
import 'modinfo.dart' as modinfo;
import 'notaconv.dart' as notaconv;
import 'render.dart' as render;

/// command → (its runner, one-line help). Aliases share a runner.
final _commands = <String, (Future<void> Function(List<String>), String)>{
  'listen': (listen.main, 'mic / WAV → live pitch & chord detection'),
  'info': (_wrap(modinfo.main), 'sniff + dump any module (.mod/.s3m/.xm/.it)'),
  'conv': (_wrap(modconv.main), 'convert modules + extract samples to WAV'),
  'render': (_wrap(render.main), 'a Loop Mixer groove → WAV'),
  'midi': (_wrap(notaconv.main), "a module's melody → Standard MIDI File"),
  'fx': (_wrap(fxproc.main), 'apply a crisp_dsp effect to a WAV'),
};

/// Adapts a synchronous `void main(args)` into an awaitable runner.
Future<void> Function(List<String>) _wrap(void Function(List<String>) m) =>
    (args) async => m(args);

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _printUsage();
    exitCode = 2;
    return;
  }
  final cmd = args.first;
  if (cmd == 'help' || cmd == '-h' || cmd == '--help') {
    _printUsage();
    return;
  }
  final entry = _commands[cmd];
  if (entry == null) {
    stderr.writeln('mus: unknown command "$cmd"');
    _printUsage();
    exitCode = 2;
    return;
  }
  await entry.$1(args.sublist(1));
}

void _printUsage() {
  stderr.writeln('usage: dart run bin/mus.dart <command> [args…]\n');
  for (final MapEntry(key: cmd, value: (_, help)) in _commands.entries) {
    stderr.writeln('  ${cmd.padRight(8)} $help');
  }
  stderr.writeln('\nRun a command with wrong args to see its own usage.');
}
