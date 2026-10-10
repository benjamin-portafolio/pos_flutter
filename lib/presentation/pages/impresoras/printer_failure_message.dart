import '../../../application/printing/printer_exception.dart';

String printerFailureMessage(PrinterFailure failure) => switch (failure) {
  PrinterFailure.unsupportedPlatform =>
    'Impresión disponible en Android por Bluetooth y en Windows mediante impresoras térmicas instaladas.',
  PrinterFailure.hardwareUnavailable => 'Este dispositivo no tiene Bluetooth.',
  PrinterFailure.bluetoothOff =>
    'Bluetooth está apagado. Actívalo en los ajustes del sistema y recarga.',
  PrinterFailure.permissionDenied =>
    'Permiso Bluetooth denegado. Puedes solicitarlo de nuevo al recargar.',
  PrinterFailure.permissionPermanentlyDenied =>
    'Permiso Bluetooth bloqueado. Habilita Dispositivos cercanos en los '
        'ajustes de permisos de esta app y recarga.',
  PrinterFailure.deviceNotBonded =>
    'El destino no está disponible. Revisa las impresoras instaladas o los dispositivos Bluetooth vinculados.',
  PrinterFailure.connectionFailed =>
    'No se pudo abrir el destino. Revisa la impresora y su configuración en el sistema.',
  PrinterFailure.writeFailed => 'No se pudo completar el envío.',
  PrinterFailure.closeFailed =>
    'No se pudo finalizar el trabajo o cerrar el destino. El servicio conserva el bloqueo de seguridad.',
  PrinterFailure.busy =>
    'El servicio de impresión está ocupado. Espera a que termine el envío y su limpieza.',
  PrinterFailure.timeout =>
    'Se agotó el tiempo de espera. Una operación pendiente conserva el bloqueo hasta terminar.',
  PrinterFailure.disposed => 'El servicio de impresión se está cerrando.',
  PrinterFailure.transportError =>
    'No se pudo completar la operación de impresión.',
  PrinterFailure.generationFailed => 'No se pudo generar el ticket térmico.',
  PrinterFailure.canceled => 'Envío cancelado antes de imprimir.',
};
