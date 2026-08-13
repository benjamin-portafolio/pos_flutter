part of '../app_database.dart';

@DriftAccessor(tables: [Products, ProductVariants])
class ProductoDao extends DatabaseAccessor<AppDatabase>
    with _$ProductoDaoMixin {
  ProductoDao(super.db);

  Stream<List<ProductoListadoRow>> watchProductosListado({
    String busqueda = '',
    Set<String> categoriaIds = const <String>{},
    bool incluirSinCategoria = false,
  }) {
    final query = select(products).join([
      leftOuterJoin(categories, categories.id.equalsExp(products.categoryId)),
      leftOuterJoin(
        productVariants,
        productVariants.productId.equalsExp(products.id) &
            productVariants.active.equals(true),
      ),
    ])..where(products.active.equals(true));

    final normalizedSearch = busqueda.trim().toLowerCase();
    if (normalizedSearch.isNotEmpty) {
      query.where(
        products.name.lower().like(
          '%${_escapeLike(normalizedSearch)}%',
          escapeChar: r'\',
        ),
      );
    }

    Expression<bool>? categoryPredicate;
    if (categoriaIds.isNotEmpty) {
      categoryPredicate = products.categoryId.isIn(categoriaIds);
    }
    if (incluirSinCategoria) {
      final withoutCategory = products.categoryId.isNull();
      categoryPredicate = categoryPredicate == null
          ? withoutCategory
          : categoryPredicate | withoutCategory;
    }
    if (categoryPredicate != null) {
      query.where(categoryPredicate);
    }

    query.orderBy([
      OrderingTerm(expression: products.name.lower()),
      OrderingTerm(expression: products.id),
      OrderingTerm(expression: productVariants.sortOrder),
      OrderingTerm(expression: productVariants.id),
    ]);

    return query.watch().map(
      (rows) => rows
          .map(
            (row) => ProductoListadoRow(
              producto: row.readTable(products),
              categoria: row.readTableOrNull(categories),
              variante: row.readTableOrNull(productVariants),
            ),
          )
          .toList(growable: false),
    );
  }

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

  Future<int> contarProductosPorCategoria(String categoryId) async {
    final count = products.id.count();
    final query = selectOnly(products)
      ..addColumns([count])
      ..where(products.categoryId.equals(categoryId));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
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

  String _escapeLike(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }
}

class ProductoListadoRow {
  const ProductoListadoRow({
    required this.producto,
    required this.categoria,
    required this.variante,
  });

  final ProductRow producto;
  final CategoryRow? categoria;
  final ProductVariantRow? variante;
}
