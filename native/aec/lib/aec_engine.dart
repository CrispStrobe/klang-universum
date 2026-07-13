// AecEngine — the plugin's Dart surface, exactly the API sketched in
// AEC_TIER3B.md. A [NativeAecEngine] drives the miniaudio full-duplex host over
// FFI: hand it the reference PCM you are about to play, it plays that AND uses
// it as the AEC far-end, and streams back the cleaned near-end (mic minus echo)
// for StreamingAudioAnalyzer / PitchDetector to consume unchanged.
//
// The device path is verified on hardware (BlackHole loopback, then on-device);
// the algorithm underneath is the same core the offline ERLE test pins down via
// [AecDsp].

import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:aec_fullduplex/src/native_library.dart';
import 'package:ffi/ffi.dart';

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

typedef _CreateC = Pointer<Void> Function(Int32, Int32);
typedef _CreateD = Pointer<Void> Function(int, int);
typedef _StartC = Int32 Function(Pointer<Void>);
typedef _StartD = int Function(Pointer<Void>);
typedef _ReferenceC = Void Function(Pointer<Void>, Pointer<Int16>, Int32);
typedef _ReferenceD = void Function(Pointer<Void>, Pointer<Int16>, int);
typedef _ReadC = Int32 Function(Pointer<Void>, Pointer<Int16>, Int32);
typedef _ReadD = int Function(Pointer<Void>, Pointer<Int16>, int);
typedef _StopC = Int32 Function(Pointer<Void>);
typedef _StopD = int Function(Pointer<Void>);
typedef _DestroyC = Void Function(Pointer<Void>);
typedef _DestroyD = void Function(Pointer<Void>);

/// FFI-backed [AecEngine] over the native `aec_engine_*` duplex host.
class NativeAecEngine implements AecEngine {
  NativeAecEngine({String? libraryPath, Duration? drainInterval})
      : _lib = openAecLibrary(libraryPath),
        _drainInterval = drainInterval ?? const Duration(milliseconds: 10);

  final DynamicLibrary _lib;
  final Duration _drainInterval;

  late final _CreateD _create =
      _lib.lookupFunction<_CreateC, _CreateD>('aec_engine_create');
  late final _StartD _start =
      _lib.lookupFunction<_StartC, _StartD>('aec_engine_start');
  late final _ReferenceD _reference =
      _lib.lookupFunction<_ReferenceC, _ReferenceD>('aec_engine_reference');
  late final _ReadD _read =
      _lib.lookupFunction<_ReadC, _ReadD>('aec_engine_read');
  late final _StopD _stop =
      _lib.lookupFunction<_StopC, _StopD>('aec_engine_stop');
  late final _DestroyD _destroy =
      _lib.lookupFunction<_DestroyC, _DestroyD>('aec_engine_destroy');

  final StreamController<Uint8List> _cleaned =
      StreamController<Uint8List>.broadcast();
  Pointer<Void> _handle = nullptr;
  Pointer<Int16>? _refBuf;
  int _refBufLen = 0;
  Pointer<Int16>? _readBuf;
  int _readCap = 0;
  Timer? _drain;

  @override
  Stream<Uint8List> get cleaned => _cleaned.stream;

  @override
  Future<void> start({int sampleRate = 44100, int frame = 256}) async {
    if (_handle != nullptr) return;
    final h = _create(sampleRate, frame);
    if (h == nullptr) {
      throw StateError('aec_engine_create($sampleRate, $frame) failed');
    }
    final rc = _start(h);
    if (rc != 0) {
      _destroy(h);
      throw StateError('aec_engine_start failed (ma_result $rc)');
    }
    _handle = h;
    _readCap = sampleRate ~/ 4; // up to ~250ms drained per tick
    _readBuf = calloc<Int16>(_readCap);
    _drain = Timer.periodic(_drainInterval, (_) => _drainCleaned());
  }

  void _drainCleaned() {
    final h = _handle;
    final buf = _readBuf;
    if (h == nullptr || buf == null || _cleaned.isClosed) return;
    final n = _read(h, buf, _readCap);
    if (n <= 0) return;
    // Copy out as PCM16 bytes (n samples * 2 bytes).
    final bytes = Uint8List(n * 2);
    final view = buf.asTypedList(n);
    final bd = ByteData.sublistView(bytes);
    for (var i = 0; i < n; i++) {
      bd.setInt16(i * 2, view[i], Endian.little);
    }
    _cleaned.add(bytes);
  }

  @override
  void reference(Uint8List pcm16) {
    final h = _handle;
    if (h == nullptr) return;
    final frames = pcm16.length ~/ 2;
    if (frames == 0) return;
    if (_refBufLen < frames) {
      if (_refBuf != null) calloc.free(_refBuf!);
      _refBuf = calloc<Int16>(frames);
      _refBufLen = frames;
    }
    final dst = _refBuf!.asTypedList(frames);
    final src = ByteData.sublistView(pcm16);
    for (var i = 0; i < frames; i++) {
      dst[i] = src.getInt16(i * 2, Endian.little);
    }
    _reference(h, _refBuf!, frames);
  }

  @override
  Future<void> stop() async {
    _drain?.cancel();
    _drain = null;
    final h = _handle;
    if (h != nullptr) {
      _stop(h);
      _destroy(h);
      _handle = nullptr;
    }
    if (_refBuf != null) {
      calloc.free(_refBuf!);
      _refBuf = null;
      _refBufLen = 0;
    }
    if (_readBuf != null) {
      calloc.free(_readBuf!);
      _readBuf = null;
      _readCap = 0;
    }
    if (!_cleaned.isClosed) await _cleaned.close();
  }
}
