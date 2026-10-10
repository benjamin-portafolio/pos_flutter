import 'dart:io';
import 'dart:isolate';

import '../../application/printing/printer_device.dart';
import '../../application/printing/printer_exception.dart';
import '../../application/printing/printer_gateway.dart';
import '../../application/printing/printer_profile.dart';
import 'windows_printer_native.dart';

typedef WindowsPrinterOperation =
    Future<Object?> Function(String operation, Map<String, Object?> arguments);

/// Each Winspool call runs on a worker isolate. Deadlines belong to the shared
/// print service: they never cancel native I/O or release its ownership early.
class WindowsPrinterGateway implements PrinterGateway, PrinterJobGateway {
  WindowsPrinterGateway({WindowsPrinterOperation? operation, bool? isWindows})
    : _operation = operation ?? _runNative,
      _supported = isWindows ?? Platform.isWindows;
  final WindowsPrinterOperation _operation;
  final bool _supported;
  int? _handle;
  bool _documentOpen = false;
  bool _operating = false;

  static Future<Object?> _runNative(String name, Map<String, Object?> args) =>
      Isolate.run(() => windowsPrinterNative(name, args));

  Future<Object?> _call(String name, Map<String, Object?> args) async {
    if (!_supported) {
      throw const PrinterException(PrinterFailure.unsupportedPlatform);
    }
    if (_operating) throw const PrinterException(PrinterFailure.busy);
    _operating = true;
    try {
      return await _operation(name, args);
    } on PrinterException {
      rethrow;
    } catch (_) {
      throw const PrinterException(PrinterFailure.transportError);
    } finally {
      _operating = false;
    }
  }

  @override
  Future<PrinterAvailability> availability() async =>
      _supported ? PrinterAvailability.ready : PrinterAvailability.unsupported;
  @override
  Future<PrinterPermission> permissionStatus() async =>
      PrinterPermission.granted;
  @override
  Future<PrinterPermission> requestPermission() => permissionStatus();
  @override
  Future<List<PrinterDevice>> listDestinations() async {
    final names = await _call('list', const {}) as List<String>;
    return List.unmodifiable(
      names.map(
        (name) => PrinterDevice(
          address: name,
          name: name,
          transport: PrinterTransport.windowsSpooler,
        ),
      ),
    );
  }

  @override
  Future<void> connect(String address) async {
    if (_handle != null) throw const PrinterException(PrinterFailure.busy);
    final result =
        await _call('open', {'name': address}) as Map<String, Object?>;
    _handle = result['handle'] as int;
    _documentOpen = result['started'] == true;
    if (!_documentOpen) {
      throw const PrinterException(PrinterFailure.connectionFailed);
    }
  }

  @override
  Future<void> write(List<int> bytes) async {
    if (_handle == null ||
        !_documentOpen ||
        bytes.isEmpty ||
        bytes.any((b) => b < 0 || b > 255)) {
      throw const PrinterException(PrinterFailure.writeFailed);
    }
    await _call('write', {'handle': _handle, 'bytes': List<int>.of(bytes)});
  }

  @override
  Future<void> finishJob({required bool commit}) async {
    if (_handle == null) return;
    final result =
        await _call('finish', {
              'handle': _handle,
              'documentOpen': _documentOpen,
              'commit': commit,
            })
            as Map<String, Object?>;
    // EndDoc/Abort must never be retried after an ambiguous result.
    _documentOpen = false;
    if (result['closed'] == true) _handle = null;
    if (result['failed'] == true) {
      throw const PrinterException(PrinterFailure.closeFailed);
    }
  }

  @override
  Future<void> close() => finishJob(commit: false);
}
