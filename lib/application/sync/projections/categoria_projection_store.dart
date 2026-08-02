import '../../../domain/categorias/color_categoria.dart';
import 'sync_projection.dart';

abstract interface class CategoriaProjectionStore {
  Future<CategoriaProjection?> findById(String id);

  Future<List<CategoriaProjection>> findAllOrdered();

  Future<void> insert(CategoriaProjection projection);

  Future<void> update(CategoriaProjection projection);

  Future<void> updateSyncMetadata(
    String id, {
    required String eventId,
    int? serverSequence,
  });

  Future<void> advanceLastServerSequence(String id, int serverSequence);

  Future<void> deleteById(String id);

  Future<void> deleteCreatedByEvent(String eventId);
}

class CategoriaProjection extends SyncProjection {
  const CategoriaProjection({
    required super.id,
    required this.nombre,
    required this.color,
    required this.orden,
    required super.active,
    required super.version,
    required super.createdEventId,
    required super.lastEventId,
    required super.lastServerSequence,
  });

  final String nombre;
  final ColorCategoria color;
  final int orden;
}
