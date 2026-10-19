import 'operacion_edicion_masiva.dart';
import 'registro_operacion_masiva.dart';
import 'resultado_operacion_masiva.dart';
import 'unidad_trabajo_masiva.dart';

/// Diario exclusivamente local. El adaptador debe proporcionar comandos,
/// lecturas, eventos y diario sobre la MISMA SQLite y transacción exterior.
/// No existe fallback serial ni ejecución al construir/abrir el adaptador.
abstract interface class DiarioEdicionMasiva {
  Future<T> transaccion<T>(
    Future<T> Function(UnidadTrabajoMasiva unidad) action,
  );
  Future<RegistroOperacionMasiva?> buscar(String operationId);
  Future<List<RegistroOperacionMasiva>> listar({
    String? batchId,
    bool soloPendientes = false,
  });
  Future<void> reservar(OperacionEdicionMasiva operacion);
  Future<void> completar(ResultadoOperacionMasiva resultado);
  Future<void> cerrarPendientes(String batchId);
}
