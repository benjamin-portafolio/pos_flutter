part of '../app_database.dart';

@DriftAccessor(tables: [Products, ProductVariants])
class ProductoDao extends DatabaseAccessor<AppDatabase>
    with _$ProductoDaoMixin {
  ProductoDao(super.db);

  Future<ProductRow?> obtenerProductoPorId(String id) {
    return (select(
      products,
    )..where((product) => product.id.equals(id))).getSingleOrNull();
  }

  Future<ProductVariantRow?> obtenerVariantePorId(String id) {
    return (select(
      productVariants,
    )..where((variant) => variant.id.equals(id))).getSingleOrNull();
  }

  Future<List<ProductVariantRow>> obtenerVariantesPorProducto(
    String productId,
  ) {
    return (select(productVariants)
          ..where((variant) => variant.productId.equals(productId))
          ..orderBy([
            (variant) => OrderingTerm(expression: variant.sortOrder),
            (variant) => OrderingTerm(expression: variant.id),
          ]))
        .get();
  }

  Future<int> insertarProducto(ProductsCompanion entity) {
    return into(products).insert(entity);
  }

  Future<int> insertarVariante(ProductVariantsCompanion entity) {
    return into(productVariants).insert(entity);
  }

  Future<void> avanzarLastServerSequence(
    String productId,
    int serverSequence,
  ) async {
    await (update(products)..where(
          (product) =>
              product.id.equals(productId) &
              (product.lastServerSequence.isNull() |
                  product.lastServerSequence.isSmallerThanValue(
                    serverSequence,
                  )),
        ))
        .write(ProductsCompanion(lastServerSequence: Value(serverSequence)));
    await (update(productVariants)..where(
          (variant) =>
              variant.productId.equals(productId) &
              (variant.lastServerSequence.isNull() |
                  variant.lastServerSequence.isSmallerThanValue(
                    serverSequence,
                  )),
        ))
        .write(
          ProductVariantsCompanion(lastServerSequence: Value(serverSequence)),
        );
  }

  Future<void> eliminarProductoPorId(String id) async {
    await (delete(
      productVariants,
    )..where((variant) => variant.productId.equals(id))).go();
    await (delete(products)..where((product) => product.id.equals(id))).go();
  }

  Future<void> eliminarProductoCreadoPorEvento(String eventId) async {
    await (delete(
      productVariants,
    )..where((variant) => variant.createdEventId.equals(eventId))).go();
    await (delete(
      products,
    )..where((product) => product.createdEventId.equals(eventId))).go();
  }
}
