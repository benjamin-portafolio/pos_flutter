import '../../../../application/edicion_masiva/cambio_variante_masiva.dart';
import 'fila_revision_masiva.dart';

/// Preparación en memoria: no tiene operationId ni reserva una ejecución.
class RevisionEdicionMasiva {
  RevisionEdicionMasiva(Iterable<FilaRevisionMasiva> filas)
    : filas = List.unmodifiable(filas);

  final List<FilaRevisionMasiva> filas;
  bool get tieneErrores => filas.any((f) => f.estado == EstadoFilaMasiva.error);

  List<CambioVarianteMasiva> get cambios {
    if (tieneErrores) {
      throw StateError('Corrige o retira las filas con errores.');
    }
    return List.unmodifiable(
      filas
          .where((f) => f.estado == EstadoFilaMasiva.cambios)
          .map((f) => f.cambio!),
    );
  }
}
