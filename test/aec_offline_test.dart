// aec_offline — the offline/streaming glue over EchoCanceller that the AEC CLI
// uses. Synthetic scenarios (a known room IR): high ERLE on echo-only, near-end
// preserved under double-talk, delay recovery, and streaming≡batch equivalence.

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/core/audio/aec_offline.dart';

const _sr = 44100;

/// A deterministic broadband-ish reference (a few sines) — excites the adaptive
/// filter across the spectrum so it can converge.
Float64List _reference(int n) {
  final r = Float64List(n);
  for (var t = 0; t < n; t++) {
    r[t] = 0.6 * sin(2 * pi * 220 * t / _sr) +
        0.3 * sin(2 * pi * 437 * t / _sr) +
        0.2 * sin(2 * pi * 911 * t / _sr);
  }
  return r;
}

/// Deterministic broadband white noise — the well-conditioned reference an
/// adaptive filter converges on fastest (and closest to real music/speech).
Float64List _noise(int n, {int seed = 7, double amp = 0.3}) {
  final rng = Random(seed);
  final r = Float64List(n);
  for (var i = 0; i < n; i++) {
    r[i] = amp * (rng.nextDouble() * 2 - 1);
  }
  return r;
}

/// A short speaker→mic impulse response (the "room"), within one block.
const _h = [0.8, -0.35, 0.2, -0.1, 0.05];

/// Echo = ref convolved with the room IR, with the whole thing delayed by
/// [delay] samples.
Float64List _echo(Float64List ref, {int delay = 0}) {
  final out = Float64List(ref.length);
  for (var t = 0; t < ref.length; t++) {
    var acc = 0.0;
    for (var j = 0; j < _h.length; j++) {
      final s = t - delay - j;
      if (s >= 0 && s < ref.length) acc += _h[j] * ref[s];
    }
    out[t] = acc;
  }
  return out;
}

/// Normalized cross-correlation of two equal-length signals over [from, to).
double _corr(Float64List a, Float64List b, int from, int to) {
  var sa = 0.0, sb = 0.0, saa = 0.0, sbb = 0.0, sab = 0.0;
  final n = to - from;
  for (var i = from; i < to; i++) {
    sa += a[i];
    sb += b[i];
    saa += a[i] * a[i];
    sbb += b[i] * b[i];
    sab += a[i] * b[i];
  }
  final cov = sab - sa * sb / n;
  final va = saa - sa * sa / n;
  final vb = sbb - sb * sb / n;
  return cov / (sqrt(va * vb) + 1e-12);
}

Uint8List _interleave(Float64List mic, Float64List ref) {
  final n = min(mic.length, ref.length);
  final bytes = Uint8List(n * 4);
  final v = ByteData.sublistView(bytes);
  for (var i = 0; i < n; i++) {
    v.setInt16(i * 4, (mic[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    v.setInt16(
      i * 4 + 2,
      (ref[i].clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  return bytes;
}

void main() {
  const n = 1024 * 40;

  test('cancels a linear echo — high ERLE', () {
    final ref = _reference(n);
    final mic = _echo(ref); // echo only, no near-end
    final result = cancelEcho(mic, ref, delay: 0);

    // Over the converged tail, the echo is deeply suppressed.
    const tail = 1024 * 24;
    final tailErle = erleDb(
      Float64List.sublistView(mic, tail, result.cleaned.length),
      Float64List.sublistView(result.cleaned, tail),
    );
    expect(
      tailErle,
      greaterThan(20),
      reason: 'tail ERLE = ${tailErle.toStringAsFixed(1)} dB',
    );
    // The whole-signal figure carries the from-scratch warmup, so it's only
    // net-positive — the converged tail above is the meaningful number.
    expect(result.erleDb, greaterThan(0), reason: 'whole-signal ERLE');
  });

  test('preserves the near-end while removing the echo (double-talk)', () {
    final ref = _reference(n);
    final echo = _echo(ref);
    // An independent near-end voice the mic also hears.
    final near = Float64List(n);
    for (var t = 0; t < n; t++) {
      near[t] = 0.4 * sin(2 * pi * 330 * t / _sr);
    }
    final mic = Float64List(n);
    for (var t = 0; t < n; t++) {
      mic[t] = echo[t] + near[t];
    }

    final result = cancelEcho(mic, ref, delay: 0);
    // The cleaned output should track the near-end, not the echo.
    const tail = 1024 * 24;
    final withNear = _corr(result.cleaned, near, tail, result.cleaned.length);
    final withEcho = _corr(result.cleaned, echo, tail, result.cleaned.length);
    expect(withNear, greaterThan(0.8), reason: 'near-end survives');
    expect(
      withNear,
      greaterThan(withEcho),
      reason: 'cleaned tracks the voice, not the speaker',
    );
  });

  test('estimateEchoDelay recovers a known lag', () {
    final ref = _reference(n);
    final mic = _echo(ref, delay: 137);
    expect(estimateEchoDelay(mic, ref), closeTo(137, 2));
  });

  test('streaming matches the batch cancel for the same aligned input', () {
    final ref = _reference(n);
    final mic = _echo(ref); // aligned (delay 0)
    final stereo = _interleave(mic, ref);

    // Decode the PCM16-quantized mic/ref exactly as the streamer sees them, so
    // the batch reference runs on byte-identical input.
    final qmic = Float64List(n), qref = Float64List(n);
    final sv = ByteData.sublistView(stereo);
    for (var i = 0; i < n; i++) {
      qmic[i] = sv.getInt16(i * 4, Endian.little) / 32768.0;
      qref[i] = sv.getInt16(i * 4 + 2, Endian.little) / 32768.0;
    }

    // Batch, quantized to PCM16 the same way the stream emits.
    final batch = cancelEcho(qmic, qref, delay: 0).cleaned;
    final batchPcm = Uint8List(batch.length * 2);
    final bv = ByteData.sublistView(batchPcm);
    for (var i = 0; i < batch.length; i++) {
      bv.setInt16(
        i * 2,
        (batch[i].clamp(-1.0, 1.0) * 32767).round(),
        Endian.little,
      );
    }

    // Stream the interleaved stereo in awkward, non-block-aligned chunks.
    final streamer = StreamingEchoCanceller();
    final acc = BytesBuilder();
    for (var off = 0; off < stereo.length; off += 777) {
      final end = min(off + 777, stereo.length);
      acc.add(
        streamer.addInterleavedPcm16(
          Uint8List.sublistView(stereo, off, end),
        ),
      );
    }
    final streamed = acc.toBytes();

    // Both drop the same trailing partial block → identical bytes.
    expect(streamed.length, batchPcm.length);
    expect(streamed, orderedEquals(batchPcm));
    // Same running-ERLE accounting as the batch pass (warmup-dominated → >0).
    expect(streamer.erleDb, greaterThan(0));
  });

  group('broadband (noise) reference', () {
    test('converges fast with high segmental ERLE + exact delay', () {
      final ref = _noise(n);
      final mic = _echo(ref, delay: 300);
      final result = cancelEcho(mic, ref); // auto delay
      expect(
        result.delay,
        closeTo(300, 1),
        reason: 'broadband ⇒ unambiguous delay',
      );

      final seg = segmentalErleDb(mic, result.cleaned);
      expect(seg, greaterThan(20), reason: 'segmental ERLE = $seg dB');

      final conv = convergenceSample(mic, result.cleaned);
      expect(conv, greaterThanOrEqualTo(0), reason: 'converged');
      expect(conv, lessThan(_sr ~/ 2), reason: 'within ~500 ms');
    });

    test('a smaller block size still cancels', () {
      final ref = _noise(n, seed: 3);
      final mic = _echo(ref);
      final out = cancelEcho(mic, ref, delay: 0, blockSize: 512).cleaned;
      expect(segmentalErleDb(mic, out, segment: 512), greaterThan(20));
    });

    test('output is finite (no NaN/Inf) under a loud reference', () {
      final ref = _noise(n, amp: 0.9);
      final out = cancelEcho(_echo(ref), ref, delay: 0).cleaned;
      expect(out.every((s) => s.isFinite), isTrue);
    });
  });

  test('far-end silence passes the near-end through untouched', () {
    // Reference silent ⇒ nothing to cancel and the VAD pauses adaptation, so
    // the mic (a pure near-end voice) must come out bit-for-bit.
    final ref = Float64List(n); // all zeros
    final near = _noise(n, seed: 11, amp: 0.4);
    final out = cancelEcho(near, ref, delay: 0).cleaned;
    for (var i = 0; i < out.length; i++) {
      expect(out[i], near[i]);
    }
  });

  group('metrics', () {
    test('siSdrDb: identical is huge, and it is scale-invariant', () {
      final s = _noise(n, seed: 5);
      expect(siSdrDb(s, s), greaterThan(100));

      // A pure overall gain is not distortion → still huge.
      final scaled = Float64List.fromList([for (final x in s) 2.0 * x]);
      expect(siSdrDb(s, scaled), greaterThan(100));

      // Adding independent noise lowers it, monotonically.
      Float64List plus(double a) {
        final ns = _noise(n, seed: 99);
        return Float64List.fromList([
          for (var i = 0; i < n; i++) s[i] + a * ns[i],
        ]);
      }

      final little = siSdrDb(s, plus(0.05));
      final lots = siSdrDb(s, plus(0.5));
      expect(little, greaterThan(lots));
      expect(lots, greaterThan(0));
    });

    test('segmentalErleDb skips silent segments and floors per-segment', () {
      final ref = _noise(n);
      final mic = _echo(ref);
      final result = cancelEcho(mic, ref, delay: 0);
      // Global vs segmental: the segmental (mean of dB) rewards the converged
      // majority and isn't dragged to ~0 by the warmup like the global figure.
      expect(segmentalErleDb(mic, result.cleaned), greaterThan(result.erleDb));

      // An all-silent pair contributes no active segments → 0, not NaN.
      final z = Float64List(4096);
      expect(segmentalErleDb(z, z), 0);
    });

    test('convergenceSample returns -1 when ERLE never reaches the target', () {
      final ref = _noise(n);
      final mic = _echo(ref);
      // "cleaned" == mic ⇒ 0 dB ERLE everywhere ⇒ never hits the target.
      expect(convergenceSample(mic, mic), -1);
    });

    test('AecMetrics.measure + report bundle the numbers', () {
      final ref = _noise(n);
      final mic = _echo(ref);
      final m = AecMetrics.measure(mic, cancelEcho(mic, ref, delay: 0).cleaned);
      expect(m.segErle, greaterThan(20));
      expect(m.convergedAtSample, greaterThanOrEqualTo(0));
      expect(m.report(), contains('converged'));
    });

    test('SI-SDR improves under converge-then-double-talk', () {
      // Filter converges on echo-only (first half), near-end joins (second).
      final ref = _noise(n);
      final echo = _echo(ref);
      final near = Float64List(n);
      for (var t = 0; t < n; t++) {
        near[t] = 0.35 * sin(2 * pi * 440 * t / _sr);
      }
      const half = n ~/ 2;
      final mic = Float64List(n);
      for (var t = 0; t < n; t++) {
        mic[t] = echo[t] + (t >= half ? near[t] : 0);
      }
      final out = cancelEcho(mic, ref, delay: 0).cleaned;
      final gain =
          siSdrDb(near, out, from: half) - siSdrDb(near, mic, from: half);
      // A positive gain (the linear core; a double-talk detector — roadmap —
      // would push this much higher).
      expect(gain, greaterThan(2), reason: 'SI-SDR gain = $gain dB');
    });
  });

  group('streaming edge cases', () {
    test('matches the batch cancel with a fixed refDelay', () {
      const d = 128;
      final ref = _noise(n);
      final mic = _echo(ref, delay: d);
      final stereo = _interleave(mic, ref);

      final qmic = Float64List(n), qref = Float64List(n);
      final sv = ByteData.sublistView(stereo);
      for (var i = 0; i < n; i++) {
        qmic[i] = sv.getInt16(i * 4, Endian.little) / 32768.0;
        qref[i] = sv.getInt16(i * 4 + 2, Endian.little) / 32768.0;
      }
      final batch = cancelEcho(qmic, qref, delay: d).cleaned;

      final streamer = StreamingEchoCanceller(refDelay: d);
      final streamed = streamer.addInterleavedPcm16(stereo);
      // Streaming holds d samples of ref latency, so it emits d fewer samples;
      // compare the overlap.
      final cmp = min(streamed.length ~/ 2, batch.length);
      final sd = ByteData.sublistView(streamed);
      for (var i = 0; i < cmp; i++) {
        final b = (batch[i].clamp(-1.0, 1.0) * 32767).round();
        expect(sd.getInt16(i * 2, Endian.little), b);
      }
      expect(cmp, greaterThan(0));
    });

    test('flush pads the final partial block; empty input is safe', () {
      final streamer = StreamingEchoCanceller();
      expect(streamer.addInterleavedPcm16(Uint8List(0)), isEmpty);
      // Feed 1.5 blocks of frames, then flush the remainder.
      final frames = (1024 * 1.5).round();
      final stereo = _interleave(_noise(frames), _noise(frames, seed: 2));
      final mid = streamer.addInterleavedPcm16(stereo); // one full block
      final tail = streamer.flush(); // the padded remainder
      expect(mid.length, 1024 * 2, reason: 'one 1024-sample block, 2 B each');
      expect(tail.length, 1024 * 2, reason: 'the padded second block');
    });

    test('empty streamer flush is a no-op', () {
      expect(StreamingEchoCanceller().flush(), isEmpty);
    });
  });
}
