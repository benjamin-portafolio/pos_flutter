import '../../../../application/edicion_masiva/resultado_operacion_masiva.dart';

/// Desenlace de un producto dentro del guardado de la captura. Un fallo no
/// deshace los commits anteriores del lote; el diario conserva su operación.
enum EstadoGuardadoMasivo { aplicada, omitida, fallida, pendiente }

class ResultadoGuardadoMasivo {
  const ResultadoGuardadoMasivo.aplicada({
    required this.productId,
    required this.resultado,
  }) : error = null,
       estado = EstadoGuardadoMasivo.aplicada;

  const ResultadoGuardadoMasivo.fallida({
    required this.productId,
    required this.error,
  }) : resultado = null,
       estado = EstadoGuardadoMasivo.fallida;

  const ResultadoGuardadoMasivo.pendiente({required this.productId})
    : resultado = null,
      error = null,
      estado = EstadoGuardadoMasivo.pendiente;
  const ResultadoGuardadoMasivo.omitida({required this.productId})
    : resultado = null,
      error = null,
      estado = EstadoGuardadoMasivo.omitida;

  final EstadoGuardadoMasivo estado;

  final String productId;
  final ResultadoOperacionMasiva? resultado;
  final Object? error;

  bool get aplicada => resultado != null;
}

/// Texto comprensible para la revisión y los resultados.
String mensajeLegibleEdicionMasiva(Object error) {
  if (error is FormatException) return error.message;
  if (error is StateError) return error.message;
  if (error is ArgumentError) return error.message ?? 'Datos inválidos.';
  return 'No se pudo completar la operación: $error';
}
