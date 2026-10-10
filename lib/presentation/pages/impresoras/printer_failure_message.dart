import '../../../application/printing/printer_exception.dart';

String printerFailureMessage(PrinterFailure failure) => switch (failure) {
  PrinterFailure.unsupportedPlatform =>
    'La impresión Bluetooth está disponible únicamente en Android.',
  PrinterFailure.hardwareUnavailable => 'Este dispositivo no tiene Bluetooth.',
  PrinterFailure.bluetoothOff =>
    'Bluetooth está apagado. Actívalo en los ajustes del sistema y recarga.',
  PrinterFailure.permissionDenied =>
    'Permiso Bluetooth denegado. Puedes solicitarlo de nuevo al recargar.',
  PrinterFailure.permissionPermanentlyDenied =>
    'Permiso Bluetooth bloqueado. Habilita Dispositivos cercanos en los '
        'ajustes de permisos de esta app y recarga.',
  PrinterFailure.deviceNotBonded =>
    'El destino ya no está vinculado. Revisa los ajustes Bluetooth del sistema.',
  PrinterFailure.connectionFailed =>
    'No se pudo conectar. Revisa que la impresora esté encendida y cerca.',
  PrinterFailure.writeFailed => 'No se pudo completar el envío.',
  PrinterFailure.closeFailed =>
    'No se pudo cerrar la conexión. El servicio conserva el bloqueo de seguridad.',
  PrinterFailure.busy =>
    'El servicio de impresión está ocupado. Espera a que termine el envío y su limpieza.',
  PrinterFailure.timeout =>
    'Se agotó el tiempo de espera. Una operación pendiente conserva el bloqueo hasta terminar.',
  PrinterFailure.disposed => 'El servicio de impresión se está cerrando.',
  PrinterFailure.transportError =>
    'No se pudo completar la operación Bluetooth.',
  PrinterFailure.generationFailed => 'No se pudo generar el ticket térmico.',
  PrinterFailure.canceled => 'Envío cancelado antes de imprimir.',
};
