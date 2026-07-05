import '../../../domain/espacios/visibilidad_espacio.dart';
import 'sync_projection.dart';

abstract interface class EspacioProjectionStore {
  Future<EspacioProjection?> findById(String id);

  Future<EspacioProjection?> findByIdentificacion(String identificacion);

  Future<void> insert(EspacioProjection projection);

  Future<void> updateSyncMetadata(
    String id, {
    required String eventId,
    int? serverSequence,
  });

  Future<void> deleteById(String id);

  Future<void> deleteCreatedByEvent(String eventId);
}

class EspacioProjection extends SyncProjection {
  const EspacioProjection({
    required super.id,
    required this.nombre,
    required this.identificacion,
    required this.visibilidad,
    required super.active,
    required super.version,
    required super.createdEventId,
    required super.lastEventId,
    required super.lastServerSequence,
  });

  final String nombre;
  final String? identificacion;
  final VisibilidadEspacio visibilidad;
}
