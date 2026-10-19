import 'operacion_edicion_masiva.dart';
import 'resultado_operacion_masiva.dart';

enum EstadoOperacionMasiva { confirmada, aplicada, cerrada }

/// El fallo deja la reserva confirmada; una revisión obsoleta se cierra
/// explícitamente. Nunca se borra evidencia de productos aplicados.
class RegistroOperacionMasiva {
  const RegistroOperacionMasiva({
    required this.operacion,
    required this.estado,
    required this.resultado,
    required this.confirmadaAt,
    required this.finalizadaAt,
  });

  final OperacionEdicionMasiva operacion;
  final EstadoOperacionMasiva estado;
  final ResultadoOperacionMasiva? resultado;
  final DateTime confirmadaAt;
  final DateTime? finalizadaAt;
}
