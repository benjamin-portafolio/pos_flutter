import '../../../application/weighing/scale_failure.dart';

String scaleFailureMessage(ScaleFailure failure) => switch (failure) {
  ScaleFailure.unsupportedPlatform =>
    'La lectura de básculas está disponible en Windows.',
  ScaleFailure.busy =>
    'Ocupada. Cierra la sesión de báscula antes de continuar.',
  ScaleFailure.deviceNotFound =>
    'El puerto guardado no está disponible. Actualiza los puertos y selecciona el destino explícitamente.',
  ScaleFailure.deviceChanged =>
    'El dispositivo de ese puerto cambió. Revisa y selecciona el destino de nuevo.',
  ScaleFailure.accessDenied =>
    'No se puede abrir el puerto. Puede estar ocupado por otra aplicación o sin permiso.',
  ScaleFailure.noResponse => 'La báscula no respondió. Revisa la conexión.',
  ScaleFailure.invalidFrame => 'Formato de lectura no compatible.',
  ScaleFailure.unsupportedUnit => 'Unidad de lectura no compatible.',
  ScaleFailure.nonPositive =>
    'Peso cero o negativo. Coloca una carga positiva.',
  ScaleFailure.unrepresentableWeight =>
    'El peso contiene una fracción de gramo no representable.',
  ScaleFailure.overflow => 'El peso excede el rango admitido.',
  ScaleFailure.stale => 'Lectura vencida. Esperando una muestra nueva.',
  ScaleFailure.closeFailed =>
    'No se confirmó el cierre del puerto. La báscula sigue reservada; reintenta cerrar.',
  ScaleFailure.invalidConfiguration =>
    'La configuración de báscula no es válida.',
  ScaleFailure.disposed => 'El servicio de básculas se cerró.',
  ScaleFailure.connectionFailed => 'No se pudo conectar con la báscula.',
  ScaleFailure.transportError => 'Se perdió la comunicación con la báscula.',
};
