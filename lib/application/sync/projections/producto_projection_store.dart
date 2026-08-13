import 'sync_projection.dart';

abstract interface class ProductoProjectionStore {
  Future<ProductoProjection?> findProductById(String id);

  Future<ProductoVarianteProjection?> findVariantById(String id);

  Future<List<ProductoVarianteProjection>> findVariantsByProductId(
    String productId,
  );

  Future<int> countProductsByCategoryId(String categoryId);

  Future<void> insertProduct(ProductoProjection projection);

  Future<void> insertVariant(ProductoVarianteProjection projection);

  Future<void> advanceLastServerSequence(String productId, int serverSequence);

  Future<void> deleteProductById(String id);

  Future<void> deleteCreatedByEvent(String eventId);
}

class ProductoProjection extends SyncProjection {
  const ProductoProjection({
    required super.id,
    required this.nombre,
    required this.categoriaId,
    required super.active,
    required super.version,
    required super.createdEventId,
    required super.lastEventId,
    required super.lastServerSequence,
  });

  final String nombre;
  final String? categoriaId;
}

class ProductoVarianteProjection extends SyncProjection {
  const ProductoVarianteProjection({
    required super.id,
    required this.productoId,
    required this.precioVentaMenor,
    required this.esPredeterminada,
    required this.orden,
    required this.comportamientoInventario,
    required super.active,
    required super.version,
    required super.createdEventId,
    required super.lastEventId,
    required super.lastServerSequence,
  });

  final String productoId;
  final int precioVentaMenor;
  final bool esPredeterminada;
  final int orden;
  final String comportamientoInventario;
}
