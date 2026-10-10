import 'package:flutter/foundation.dart';
import '../../application/printing/printer_gateway.dart';
import 'android_bluetooth_printer_gateway.dart';
import 'windows_printer_gateway.dart';

/// Construction performs no enumeration, permission request or print job.
PrinterGateway createPrinterGateway({TargetPlatform? platform, bool? isWeb}) {
  final target = platform ?? defaultTargetPlatform;
  if (!(isWeb ?? kIsWeb) && target == TargetPlatform.windows) {
    return WindowsPrinterGateway();
  }
  return AndroidBluetoothPrinterGateway(
    isAndroid: !(isWeb ?? kIsWeb) && target == TargetPlatform.android,
  );
}
