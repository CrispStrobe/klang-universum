// live_check.dart — real-device diagnostics for the native duplex host.
//
// NOT a unit test (deliberately outside test/ so `dart test` / CI never opens a
// real audio device). Run manually on a machine with audio hardware:
//
//   cmake --build native/aec/build
//   dart run native/aec/tool/live_check.dart
//
// Two checks:
//   1. LIFECYCLE — start the duplex device on miniaudio's `null` backend and
//      confirm the realtime callback actually fires (cleaned frames flow at
//      ~sample rate). Proves the device/threading/ring path end to end, with no
//      hardware and no mic-permission prompt.
//   2. BLACKHOLE LOOPBACK — route both playback and capture through the
//      "BlackHole 2ch" virtual loopback (system default untouched), play white
//      noise as the reference, and measure the acoustic round-trip DELAY (via
//      cross-correlation of what we sent vs the raw mic) and the ERLE (raw vs
//      cleaned energy). This is milestone (b): cancellation on real device audio.

import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:aec_fullduplex/src/engine_ffi.dart';

const int kSampleRate = 44100;

String _resolveLib() {
  final env = Platform.environment['AEC_LIBRARY_PATH'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) return env;
  final ext = Platform.isMacOS
      ? 'dylib'
      : Platform.isWindows
          ? 'dll'
          : 'so';
  final prefix = Platform.isWindows ? '' : 'lib';
  for (final dir in ['native/aec/build', 'build', 'build/Release']) {
    final p = '$dir/${prefix}aec.$ext';
    if (File(p).existsSync()) return p;
  }
  stderr.writeln(
      'native library not found — run: cmake --build native/aec/build');
  exit(2);
}

bool _lifecycleCheck(String lib) {
  stdout.writeln('\n── 1. duplex lifecycle (null backend) ─────────────────');
  final e = AecEngineFfi.create(
      sampleRate: kSampleRate, frame: 256, libraryPath: lib);
  try {
    final rc = e.startNull();
    if (rc != 0) {
      stdout.writeln('  FAIL: startNull returned $rc');
      return false;
    }
    // Feed ~500ms of a tone as reference; the null mic delivers silence.
    var produced = 0;
    final target = (kSampleRate * 0.5).round();
    while (produced < target) {
      final chunk = Int16List(1470); // ~33ms
      for (var i = 0; i < chunk.length; i++) {
        final t = produced + i;
        chunk[i] = (0.3 * sin(2 * pi * 220 * t / kSampleRate) * 32767).round();
      }
      e.reference(chunk);
      produced += chunk.length;
      sleep(const Duration(milliseconds: 33));
    }
    sleep(const Duration(milliseconds: 150));
    final cleaned = e.read();
    final raw = e.readRaw();
    e.stop();
    final flowed = cleaned.length;
    final pct = (flowed / target * 100).toStringAsFixed(0);
    stdout.writeln('  callbacks produced $flowed cleaned frames '
        '(~$pct% of a $target-frame feed window)');
    stdout.writeln(
        '  raw mic energy (null backend → expect ~0): ${_rms(raw).toStringAsFixed(1)}');
    final ok = flowed > kSampleRate ~/ 8; // clearly ran in realtime
    stdout.writeln(ok
        ? '  PASS: duplex callback ran and the pipeline flowed'
        : '  FAIL: too few frames — callback may not have fired');
    return ok;
  } finally {
    e.dispose();
  }
}

bool _loopbackCheck(String lib) {
  stdout.writeln('\n── 2. BlackHole loopback ERLE ─────────────────────────');
  // Short device period keeps the round-trip delay small; the longer AEC block
  // (4096) covers it comfortably.
  const frame = 4096;
  final e = AecEngineFfi.create(
      sampleRate: kSampleRate, frame: frame, libraryPath: lib);
  try {
    e.setPeriod(256);
    final rc = e.startNamed(playback: 'BlackHole', capture: 'BlackHole');
    if (rc != 0) {
      stdout.writeln('  SKIP: could not open BlackHole duplex (rc=$rc). '
          'Is "BlackHole 2ch" installed?');
      return true; // not a failure of the code under test
    }

    final rng = Random(3);
    final sent = <int>[];
    final rawAll = <int>[];
    final cleanedAll = <int>[];
    const seconds = 3;
    final target = kSampleRate * seconds;
    var produced = 0;
    while (produced < target) {
      final chunk = Int16List(1470); // ~33ms of white noise
      for (var i = 0; i < chunk.length; i++) {
        chunk[i] = ((rng.nextDouble() * 2 - 1) * 0.3 * 32767).round();
      }
      e.reference(chunk);
      sent.addAll(chunk);
      produced += chunk.length;
      sleep(const Duration(milliseconds: 33));
      rawAll.addAll(e.readRaw());
      cleanedAll.addAll(e.read());
    }
    sleep(const Duration(milliseconds: 300));
    rawAll.addAll(e.readRaw());
    cleanedAll.addAll(e.read());
    e.stop();

    stdout.writeln('  sent ${sent.length}, raw ${rawAll.length}, '
        'cleaned ${cleanedAll.length} frames');
    if (rawAll.length < kSampleRate || cleanedAll.length < kSampleRate) {
      stdout
          .writeln('  FAIL: too little audio returned — loopback not flowing');
      return false;
    }

    // End-to-end queue→mic latency (cross-correlate what we queued vs the raw
    // mic). NB this is dominated by app-side reference-ring buffering (how fast
    // we fed), NOT the AEC-relevant playback→capture hardware delay — the AEC
    // uses the reference at play time, so the delay it must model is only the
    // hardware loopback latency, which the ERLE below shows is within the
    // filter tail.
    final delay = _estimateDelay(sent, rawAll);
    final delayMs = (delay / kSampleRate * 1000).toStringAsFixed(1);
    stdout
        .writeln('  end-to-end queue→mic latency: $delay frames ($delayMs ms) '
            '[incl. app-side ref buffering]');

    // ERLE over the last second (steady state): raw vs cleaned energy.
    final tail = kSampleRate;
    final rawTail = rawAll.sublist(rawAll.length - tail);
    final cleanTail = cleanedAll.sublist(cleanedAll.length - tail);
    final rawE = _energy(rawTail);
    final cleanE = _energy(cleanTail);
    final erle = 10 * (log(rawE / (cleanE + 1e-9)) / ln10);
    stdout.writeln('  raw RMS ${_rms(rawTail).toStringAsFixed(1)}, '
        'cleaned RMS ${_rms(cleanTail).toStringAsFixed(1)}');
    stdout.writeln('  ERLE (raw→cleaned): ${erle.toStringAsFixed(1)} dB');

    final ok = erle > 6.0; // real acoustic cancellation, not just plumbing
    stdout.writeln(ok
        ? '  PASS: the native AEC cancels real loopback echo (>6 dB ERLE)'
        : '  NOTE: low ERLE — delay likely exceeds the filter tail; needs delay '
            'tracking (milestone e). Plumbing works; cancellation needs tuning.');
    return ok;
  } finally {
    e.dispose();
  }
}

int _estimateDelay(List<int> sent, List<int> recv) {
  // Correlate a 0.5s window from ~1s into both streams, over lags 0..8192.
  const win = 22050;
  const maxLag = 8192;
  final s0 = kSampleRate; // skip 1s startup
  if (sent.length < s0 + win || recv.length < s0 + win + maxLag) return -1;
  var best = 0;
  var bestScore = -double.infinity;
  for (var lag = 0; lag < maxLag; lag++) {
    var dot = 0.0;
    for (var i = 0; i < win; i += 4) {
      // subsample x4 for speed
      dot += sent[s0 + i].toDouble() * recv[s0 + i + lag];
    }
    if (dot > bestScore) {
      bestScore = dot;
      best = lag;
    }
  }
  return best;
}

double _energy(List<int> x) {
  var s = 0.0;
  for (final v in x) {
    s += v.toDouble() * v;
  }
  return s;
}

double _rms(List<int> x) => x.isEmpty ? 0 : sqrt(_energy(x) / x.length);

void main() {
  final lib = _resolveLib();
  stdout.writeln('AEC live check — library: $lib');
  // Touch the FFI type so the import is unambiguously used even if checks skip.
  assert(sizeOf<Int16>() == 2);
  final a = _lifecycleCheck(lib);
  final b = _loopbackCheck(lib);
  stdout.writeln('\n════ lifecycle: ${a ? "PASS" : "FAIL"} · '
      'loopback: ${b ? "PASS/SKIP" : "FAIL"} ════');
  exit((a && b) ? 0 : 1);
}
