import 'cliente_creado_payload.dart';

class ClienteActualizadoPayload {
  ClienteActualizadoPayload({
    required this.baseEventId,
    required this.before,
    required this.after,
  }) {
    if (baseEventId.trim().isEmpty) {
      throw const FormatException('Falta el evento base del cliente.');
    }
  }
  static const aggregateType = 'cliente';
  static const eventType = 'cliente_actualizado';
  final String baseEventId;
  final ClienteCreadoPayload before;
  final ClienteCreadoPayload after;

  factory ClienteActualizadoPayload.fromJson(Map<String, Object?> json) {
    if (json['base_event_id'] is! String ||
        json['before'] is! Map ||
        json['after'] is! Map) {
      throw const FormatException('Actualización de cliente inválida.');
    }
    return ClienteActualizadoPayload(
      baseEventId: json['base_event_id'] as String,
      before: ClienteCreadoPayload.fromJson(
        Map<String, Object?>.from(json['before'] as Map),
      ),
      after: ClienteCreadoPayload.fromJson(
        Map<String, Object?>.from(json['after'] as Map),
      ),
    );
  }
  static bool sameState(ClienteCreadoPayload a, ClienteCreadoPayload b) =>
      a.nombre == b.nombre && a.telefono == b.telefono;
  Map<String, Object?> toJson() => {
    'base_event_id': baseEventId,
    'before': before.toJson(),
    'after': after.toJson(),
  };
}
