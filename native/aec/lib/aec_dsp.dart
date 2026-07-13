// Low-level Dart binding to the pure MIT echo-canceller (aec_dsp.h).
//
// This is the offline, device-free layer: it exercises exactly the same
// algorithm as lib/core/audio/echo_canceller.dart, so the ERLE cross-check test
// can assert the C port matches the Dart core. Callers manage lifetime with
// [create]/[dispose].

import 'dart:ffi';
import 'dart:typed_data';

import 'package:aec_fullduplex/src/native_library.dart';
import 'package:ffi/ffi.dart';

typedef _CreateDefaultC = Pointer<Void> Function(Int32);
typedef _CreateDefaultD = Pointer<Void> Function(int);
typedef _ProcessC = Void Function(
    Pointer<Void>, Pointer<Double>, Pointer<Double>, Pointer<Double>);
typedef _ProcessD = void Function(
    Pointer<Void>, Pointer<Double>, Pointer<Double>, Pointer<Double>);
typedef _VoidPtrC = Void Function(Pointer<Void>);
typedef _VoidPtrD = void Function(Pointer<Void>);

/// A single adaptive-filter instance backed by the native `aec_dsp_*` core.
class AecDsp {
  AecDsp._(this._lib, this._handle, this.blockSize)
      : _ref = calloc<Double>(blockSize),
        _mic = calloc<Double>(blockSize),
        _out = calloc<Double>(blockSize);

  /// Open the native library (see [openAecLibrary]) and create a canceller with
  /// the Dart `EchoCanceller` defaults for [blockSize] (a power of two).
  factory AecDsp.create({int blockSize = 1024, String? libraryPath}) {
    final lib = openAecLibrary(libraryPath);
    final create = lib.lookupFunction<_CreateDefaultC, _CreateDefaultD>(
        'aec_dsp_create_default');
    final handle = create(blockSize);
    if (handle == nullptr) {
      throw StateError('aec_dsp_create_default($blockSize) returned null '
          '(blockSize must be a power of two)');
    }
    return AecDsp._(lib, handle, blockSize);
  }

  final DynamicLibrary _lib;
  final Pointer<Void> _handle;
  final int blockSize;
  final Pointer<Double> _ref;
  final Pointer<Double> _mic;
  final Pointer<Double> _out;
  bool _disposed = false;

  late final _ProcessD _process =
      _lib.lookupFunction<_ProcessC, _ProcessD>('aec_dsp_process');
  late final _VoidPtrD _reset =
      _lib.lookupFunction<_VoidPtrC, _VoidPtrD>('aec_dsp_reset');
  late final _VoidPtrD _destroy =
      _lib.lookupFunction<_VoidPtrC, _VoidPtrD>('aec_dsp_destroy');

  /// Cancel the echo of [reference] from [mic] (both [blockSize] long,
  /// time-aligned). Returns the near-end estimate (a fresh [Float64List]).
  Float64List process(Float64List reference, Float64List mic) {
    assert(reference.length == blockSize && mic.length == blockSize);
    final rv = _ref.asTypedList(blockSize);
    final mv = _mic.asTypedList(blockSize);
    rv.setAll(0, reference);
    mv.setAll(0, mic);
    _process(_handle, _ref, _mic, _out);
    return Float64List.fromList(_out.asTypedList(blockSize));
  }

  void reset() => _reset(_handle);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _destroy(_handle);
    calloc.free(_ref);
    calloc.free(_mic);
    calloc.free(_out);
  }
}
