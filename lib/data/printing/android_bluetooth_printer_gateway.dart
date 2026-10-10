import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pos_bluetooth_printer/pos_bluetooth_printer.dart';

import '../../application/printing/printer_device.dart';
import '../../application/printing/printer_exception.dart';
import '../../application/printing/printer_gateway.dart';

class AndroidBluetoothPrinterGateway implements PrinterGateway {
  AndroidBluetoothPrinterGateway({
    MethodChannel channel = posBluetoothPrinterChannel,
    bool? isAndroid,
  }) : _channel = channel,
       _supported =
           isAndroid ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final MethodChannel _channel;
  final bool _supported;

  Future<T?> _call<T>(String method, [Object? arguments]) async {
    if (!_supported) {
      throw const PrinterException(PrinterFailure.unsupportedPlatform);
    }
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw PrinterException(switch (error.code) {
        'no_hardware' => PrinterFailure.hardwareUnavailable,
        'bluetooth_off' => PrinterFailure.bluetoothOff,
        'permission_denied' => PrinterFailure.permissionDenied,
        'permission_permanently_denied' =>
          PrinterFailure.permissionPermanentlyDenied,
        'device_not_bonded' => PrinterFailure.deviceNotBonded,
        'connection_failed' => PrinterFailure.connectionFailed,
        'write_failed' => PrinterFailure.writeFailed,
        'close_failed' => PrinterFailure.closeFailed,
        'busy' => PrinterFailure.busy,
        'timeout' => PrinterFailure.timeout,
        _ => PrinterFailure.transportError,
      });
    } on MissingPluginException {
      throw const PrinterException(PrinterFailure.unsupportedPlatform);
    }
  }

  @override
  Future<PrinterAvailability> availability() async {
    if (!_supported) return PrinterAvailability.unsupported;
    return switch (await _call<String>('availability')) {
      'ready' => PrinterAvailability.ready,
      'off' => PrinterAvailability.off,
      'no_hardware' => PrinterAvailability.noHardware,
      'permission_required' => PrinterAvailability.permissionRequired,
      _ => throw const PrinterException(PrinterFailure.transportError),
    };
  }

  Future<PrinterPermission> _permission(String method) async =>
      switch (await _call<String>(method)) {
        'granted' => PrinterPermission.granted,
        'denied' => PrinterPermission.denied,
        'permanently_denied' => PrinterPermission.permanentlyDenied,
        _ => throw const PrinterException(PrinterFailure.transportError),
      };

  @override
  Future<PrinterPermission> permissionStatus() =>
      _permission('permissionStatus');
  @override
  Future<PrinterPermission> requestPermission() =>
      _permission('requestPermission');
  @override
  Future<List<PrinterDevice>> bondedDevices() async {
    final devices = await _call<List<dynamic>>('bondedDevices');
    if (devices == null) {
      throw const PrinterException(PrinterFailure.transportError);
    }
    return List.unmodifiable(
      devices.map(
        (dynamic device) => PrinterDevice(
          address: device['address'] as String,
          name: device['name'] as String?,
        ),
      ),
    );
  }

  @override
  Future<void> connect(String address) async {
    await _call<void>('connect', address);
  }

  @override
  Future<void> write(List<int> bytes) async {
    await _call<void>('write', Uint8List.fromList(bytes));
  }

  @override
  Future<void> close() async {
    if (_supported) await _call<void>('close');
  }
}
