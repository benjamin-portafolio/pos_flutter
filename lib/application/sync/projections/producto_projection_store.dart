import '../../../domain/articulos/sale_configuration.dart';
import 'sync_projection.dart';

abstract interface class ProductoProjectionStore {
  Future<ProductoProjection?> findProductById(String id);

  Future<ProductoVarianteProjection?> findVariantById(String id);

  Future<ProductoVarianteProjection?> findVariantByInventoryItemId(
    String inventoryItemId,
  );

  Future<List<ProductoVarianteProjection>> findVariantsByProductId(
    String productId,
  );

  Future<List<ProductoProjection>> findProductsByCategoryId(String categoryId);

  Future<void> insertProduct(ProductoProjection projection);

  Future<void> insertVariant(ProductoVarianteProjection projection);

  Future<void> insertRecipeComponent(
    ProductoRecetaComponenteProjection projection,
  );

  Future<void> updateProduct(ProductoProjection projection);

  Future<void> advanceLastServerSequence(String productId, int serverSequence);

  Future<void> advanceProductLastServerSequence(
    String productId,
    int serverSequence,
  );

  Future<void> deleteProductById(String id);

  Future<void> deleteCreatedByEvent(String eventId);
}

class ProductoProjection extends SyncProjection {
  const ProductoProjection({
    required super.id,
    required this.nombre,
    required this.categoriaId,
    this.saleConfiguration = const UnitSaleConfiguration(),
    required super.active,
    required super.version,
    required super.createdEventId,
    required super.lastEventId,
    required super.lastServerSequence,
  });

  final String nombre;
  final String? categoriaId;
  final SaleConfiguration saleConfiguration;
}

class ProductoVarianteProjection extends SyncProjection {
  const ProductoVarianteProjection({
    required super.id,
    required this.productoId,
    this.nombre,
    this.nameKey,
    required this.precioVentaMenor,
    this.costoEstandarMenor,
    this.inventoryItemId,
    required this.esPredeterminada,
    required this.orden,
    required super.active,
    required super.version,
    required super.createdEventId,
    required super.lastEventId,
    required super.lastServerSequence,
  });

  final String productoId;
  final String? nombre;
  final String? nameKey;
  final int precioVentaMenor;
  final int? costoEstandarMenor;
  final String? inventoryItemId;
  final bool esPredeterminada;
  final int orden;
}

class ProductoRecetaComponenteProjection {
  const ProductoRecetaComponenteProjection({
    required this.varianteId,
    required this.inventoryItemId,
    required this.quantityAtomic,
  });

  final String varianteId;
  final String inventoryItemId;
  final int quantityAtomic;
}
