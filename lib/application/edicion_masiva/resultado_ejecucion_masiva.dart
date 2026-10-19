import 'operacion_edicion_masiva.dart';
import 'resultado_operacion_masiva.dart';

/// Resultado por producto: los errores no deshacen los otros commits del lote.
class ResultadoEjecucionMasiva {
  const ResultadoEjecucionMasiva({
    required this.operacion,
    this.resultado,
    this.error,
  });
  final OperacionEdicionMasiva operacion;
  final ResultadoOperacionMasiva? resultado;
  final Object? error;
}
