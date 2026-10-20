import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../../application/weighing/scale_device.dart';
import '../../application/weighing/scale_exception.dart';
import '../../application/weighing/scale_failure.dart';
import '../../application/weighing/scale_gateway.dart';
import '../../application/weighing/scale_measurement.dart';
import '../../application/weighing/scale_profile.dart';
import 'rhino_bar8rs_protocol.dart';
import 'windows_scale_native.dart';

typedef WindowsScaleOperation =
    Future<Object?> Function(String operation, Map<String, Object?> arguments);

/// Every native operation runs in a worker isolate. Bounded synchronous I/O
/// completes before closing; no Future.timeout, abandoned worker or handle.
class WindowsScaleGateway implements ScaleGateway {
  WindowsScaleGateway({WindowsScaleOperation? operation, bool? isWindows})
    : _operation = operation ?? _runNative,
      _supported = isWindows ?? Platform.isWindows;

  final WindowsScaleOperation _operation;
  final bool _supported;
  final _protocol = RhinoBar8RsProtocol();
  Future<void>? _pending;
  Future<void>? _closingFuture;
  bool _closing = false;
  int? _handle;

  static Future<Object?> _runNative(String name, Map<String, Object?> args) =>
      Isolate.run(() => windowsScaleNative(name, args));

  Future<T> _exclusive<T>(Future<T> Function() work) async {
    if (!_supported) {
      throw const ScaleException(ScaleFailure.unsupportedPlatform);
    }
    if (_pending != null || _closing) {
      throw const ScaleException(ScaleFailure.busy);
    }
    // This future only signals native completion, so close can await it even
    // when the caller receives an operation error.
    final completed = Completer<void>();
    _pending = completed.future;
    try {
      return await work();
    } on ScaleException {
      rethrow;
    } catch (_) {
      throw const ScaleException(ScaleFailure.transportError);
    } finally {
      _pending = null;
      completed.complete();
    }
  }

  Future<List<ScaleDevice>> _listNative() async {
    final rows = await _operation('list', const {}) as List<Object?>;
    return List.unmodifiable(
      rows.map((row) {
        final data = row as Map<String, Object?>;
        return ScaleDevice(
          port: data['port'] as String,
          name: data['name'] as String,
          systemId: data['systemId'] as String,
        );
      }),
    );
  }

  @override
  Future<List<ScaleDevice>> listDevices() => _exclusive(() async {
    // A refresh must not occupy the gateway between two queries of the active
    // lease and make its next read fail with busy.
    if (_handle != null) throw const ScaleException(ScaleFailure.busy);
    return _listNative();
  });

  @override
  Future<void> open(ScaleProfile profile) => _exclusive(() async {
    if (_handle != null) throw const ScaleException(ScaleFailure.busy);
    final devices = await _listNative();
    final matches = devices.where((device) => device.port == profile.port);
    if (matches.isEmpty) {
      throw const ScaleException(ScaleFailure.deviceNotFound);
    }
    if (matches.single.systemId.toUpperCase() !=
        profile.systemId.toUpperCase()) {
      throw const ScaleException(ScaleFailure.deviceChanged);
    }
    // close may have been requested during enumeration; do not start opening.
    if (_closing) return;
    final result =
        await _operation('open', {
              'port': profile.port,
              'baudRate': profile.serial.baudRate,
              'dataBits': profile.serial.dataBits,
              'parity': profile.serial.parity,
              'stopBits': profile.serial.stopBits,
            })
            as Map<String, Object?>;
    _handle = result['handle'] as int;
    _protocol.reset();
    if (result['configured'] != true) {
      // Retain the handle even on failed configuration. The session closes it
      // and cannot release its lease until CloseHandle actually succeeds.
      throw ScaleException(
        ScaleFailure.invalidConfiguration,
        nativeCode: result['error'] as int?,
      );
    }
  });

  @override
  Future<List<ScaleMeasurement>> readWeight() => _exclusive(() async {
    if (_handle == null) {
      throw const ScaleException(ScaleFailure.connectionFailed);
    }
    final bytes = await _operation('query', {'handle': _handle}) as List<int>;
    final readings = _protocol.add(bytes);
    if (readings.isEmpty) {
      // Never issue another request after a partial/late response. Close the
      // session instead, preventing old bytes from satisfying a new request.
      throw const ScaleException(ScaleFailure.noResponse);
    }
    return readings;
  });

  @override
  Future<void> close() {
    if (!_supported) return Future.value();
    return _closingFuture ??= _close().whenComplete(
      () => _closingFuture = null,
    );
  }

  Future<void> _close() async {
    _closing = true;
    await _pending;
    if (_handle != null) {
      final closed = await _operation('close', {'handle': _handle});
      if (closed != true) throw const ScaleException(ScaleFailure.closeFailed);
      _handle = null;
    }
    _protocol.reset();
    _closing = false;
  }
}
