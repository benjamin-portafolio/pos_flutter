import 'proveedor_creado_payload.dart';
import 'supplier_json.dart';

/// Edición con estados completos para validar la base y permitir reversión.
class ProveedorActualizadoPayload {
  ProveedorActualizadoPayload({
    required String baseEventId,
    required this.before,
    required this.after,
  }) : baseEventId = SupplierJson.uuid(baseEventId, 'base_event_id');

  static const aggregateType = 'supplier';
  static const eventType = 'proveedor_actualizado';
  final String baseEventId;
  final ProveedorCreadoPayload before;
  final ProveedorCreadoPayload after;

  factory ProveedorActualizadoPayload.fromJson(Map<String, Object?> json) =>
      ProveedorActualizadoPayload(
        baseEventId: SupplierJson.uuid(json['base_event_id'], 'base_event_id'),
        before: ProveedorCreadoPayload.fromJson(
          SupplierJson.object(json['before'], 'before'),
        ),
        after: ProveedorCreadoPayload.fromJson(
          SupplierJson.object(json['after'], 'after'),
        ),
      );

  static bool sameState(ProveedorCreadoPayload a, ProveedorCreadoPayload b) =>
      a.name == b.name && a.phone == b.phone && a.notes == b.notes;

  Map<String, Object?> toJson() => {
    'base_event_id': baseEventId,
    'before': before.toJson(),
    'after': after.toJson(),
  };
}
