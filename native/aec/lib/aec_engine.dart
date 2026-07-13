// AecEngine — the plugin's app-facing Dart surface, exactly the API sketched in
// AEC_TIER3B.md. A [NativeAecEngine] drives the miniaudio full-duplex host over
// FFI (via the low-level [AecEngineFfi]): hand it the reference PCM you are
// about to play, it plays that AND uses it as the AEC far-end, and streams back
// the cleaned near-end (mic minus echo) for StreamingAudioAnalyzer /
// PitchDetector to consume unchanged.
//
// The device path is verified on hardware (BlackHole loopback, then on-device);
// the algorithm underneath is the same core the offline ERLE test pins down via
// [AecDsp], and the int16 ring/framing path is pinned by the headless engine
// unit test via [AecEngineFfi].

import 'dart:async';
import 'dart:typed_data';

import 'package:aec_fullduplex/src/engine_ffi.dart';

/// The full-duplex echo-cancelling capture engine.
abstract class AecEngine {
  /// Open the duplex device and begin playback+capture. [frame] is the AEC
  /// block size (a power of two).
  Future<void> start({int sampleRate = 44100, int frame = 256});

  /// Queue PCM16 (mono, little-endian) to be played AND cancelled.
  void reference(Uint8List pcm16);

  /// Cleaned near-end (mic minus echo), delivered in chunks as they're ready.
  Stream<Uint8List> get cleaned;

  /// Stop the device and end [cleaned]. Safe to call more than once.
  Future<void> stop();
}

/// FFI-backed [AecEngine] over the native `aec_engine_*` duplex host.
class NativeAecEngine implements AecEngine {
  NativeAecEngine({String? libraryPath, Duration? drainInterval})
      : _libraryPath = libraryPath,
        _drainInterval = drainInterval ?? const Duration(milliseconds: 10);

  final String? _libraryPath;
  final Duration _drainInterval;

  final StreamController<Uint8List> _cleaned =
      StreamController<Uint8List>.broadcast();
  AecEngineFfi? _ffi;
  Timer? _drain;

  @override
  Stream<Uint8List> get cleaned => _cleaned.stream;

  @override
  Future<void> start({int sampleRate = 44100, int frame = 256}) async {
    if (_ffi != null) return;
    final ffi = AecEngineFfi.create(
      sampleRate: sampleRate,
      frame: frame,
      libraryPath: _libraryPath,
    );
    final rc = ffi.start();
    if (rc != 0) {
      ffi.dispose();
      throw StateError('aec_engine_start failed (ma_result $rc)');
    }
    _ffi = ffi;
    _drain = Timer.periodic(_drainInterval, (_) => _drainCleaned());
  }

  void _drainCleaned() {
    final ffi = _ffi;
    if (ffi == null || _cleaned.isClosed) return;
    final samples = ffi.read();
    if (samples.isEmpty) return;
    _cleaned.add(Uint8List.sublistView(samples));
  }

  @override
  void reference(Uint8List pcm16) {
    _ffi?.reference(Int16List.sublistView(pcm16));
  }

  @override
  Future<void> stop() async {
    _drain?.cancel();
    _drain = null;
    final ffi = _ffi;
    if (ffi != null) {
      ffi.stop();
      ffi.dispose();
      _ffi = null;
    }
    if (!_cleaned.isClosed) await _cleaned.close();
  }
}
