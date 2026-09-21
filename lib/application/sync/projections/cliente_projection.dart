import 'sync_projection.dart';

class ClienteProjection extends SyncProjection {
  const ClienteProjection({
    required super.id,
    required this.nombre,
    required this.telefono,
    required super.active,
    required super.version,
    required super.createdEventId,
    required super.lastEventId,
    required super.lastServerSequence,
  });
  final String nombre;
  final String? telefono;
}
