import '../payloads/proveedor_creado_payload.dart';
import 'sync_projection.dart';

class ProveedorProjection extends SyncProjection {
  const ProveedorProjection({
    required super.id,
    required this.name,
    required this.phone,
    required this.notes,
    required super.active,
    required super.version,
    required super.createdEventId,
    required super.lastEventId,
    required super.lastServerSequence,
  });

  final String name;
  final String? phone;
  final String? notes;

  ProveedorCreadoPayload get state =>
      ProveedorCreadoPayload(name: name, phone: phone, notes: notes);
}
