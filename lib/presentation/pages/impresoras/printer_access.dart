import 'dart:async';

import '../../../application/printing/printer_exception.dart';
import '../../../application/printing/printer_gateway.dart';

/// Only called after an explicit UI action. A late permission result must not
/// continue into listing or printing after that route has closed.
Future<bool> requestPrinterAccess(
  PrinterGateway gateway, {
  required bool Function() isActive,
  // A print already owns a draining deadline in TicketPrintService.
  Duration? timeout = const Duration(seconds: 35),
}) async {
  Future<T> bounded<T>(Future<T> operation) =>
      timeout == null ? operation : operation.timeout(timeout);
  try {
    var availability = await bounded(gateway.availability());
    if (!isActive()) return false;
    void validate(PrinterAvailability state) {
      final failure = switch (state) {
        PrinterAvailability.unsupported => PrinterFailure.unsupportedPlatform,
        PrinterAvailability.noHardware => PrinterFailure.hardwareUnavailable,
        PrinterAvailability.off => PrinterFailure.bluetoothOff,
        _ => null,
      };
      if (failure != null) throw PrinterException(failure);
    }

    validate(availability);
    var permission = await bounded(gateway.permissionStatus());
    if (!isActive()) return false;
    if (permission == PrinterPermission.denied) {
      permission = await bounded(gateway.requestPermission());
      if (!isActive()) return false;
    }
    if (permission != PrinterPermission.granted) {
      throw PrinterException(
        permission == PrinterPermission.permanentlyDenied
            ? PrinterFailure.permissionPermanentlyDenied
            : PrinterFailure.permissionDenied,
      );
    }
    availability = await bounded(gateway.availability());
    if (!isActive()) return false;
    validate(availability);
    if (availability != PrinterAvailability.ready) {
      throw const PrinterException(PrinterFailure.permissionDenied);
    }
    return true;
  } on TimeoutException {
    throw const PrinterException(PrinterFailure.timeout);
  }
}
