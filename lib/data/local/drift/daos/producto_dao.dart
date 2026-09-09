part of '../app_database.dart';

@DriftAccessor(tables: [Products, ProductVariants, RecipeComponents])
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
      final pattern = '%${_escapeLike(normalizedSearch)}%';
      query.where(
        products.name.lower().like(pattern, escapeChar: r'\') |
            productVariants.name.lower().like(pattern, escapeChar: r'\'),
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

  Future<ProductVariantRow?> obtenerVariantePorInventoryItemId(
    String inventoryItemId,
  ) {
    return (select(productVariants)
          ..where((variant) => variant.inventoryItemId.equals(inventoryItemId)))
        .getSingleOrNull();
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

  Future<List<ProductRow>> obtenerProductosPorCategoria(String categoryId) {
    return (select(products)
          ..where((product) => product.categoryId.equals(categoryId))
          ..orderBy([(product) => OrderingTerm(expression: product.id)]))
        .get();
  }

  Future<int> insertarProducto(ProductsCompanion entity) {
    return into(products).insert(entity);
  }

  Future<int> insertarVariante(ProductVariantsCompanion entity) {
    return into(productVariants).insert(entity);
  }

  Future<int> insertarComponenteReceta(RecipeComponentsCompanion entity) {
    return into(recipeComponents).insert(entity);
  }

  Future<List<RecipeComponentRow>> obtenerComponentesRecetaPorVariante(
    String variantId,
  ) {
    return (select(recipeComponents)
          ..where((component) => component.variantId.equals(variantId))
          ..orderBy([
            (component) => OrderingTerm(expression: component.inventoryItemId),
          ]))
        .get();
  }

  Future<void> actualizarProducto(
    String productId,
    ProductsCompanion entity,
  ) async {
    await (update(
      products,
    )..where((product) => product.id.equals(productId))).write(entity);
  }

  Future<void> avanzarLastServerSequence(
    String productId,
    int serverSequence,
  ) async {
    await descartarRespaldosConfirmados(productId);
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

  Future<void> avanzarLastServerSequenceProducto(
    String productId,
    int serverSequence,
  ) async {
    await descartarRespaldosConfirmados(productId);
    await (update(products)..where(
          (product) =>
              product.id.equals(productId) &
              (product.lastServerSequence.isNull() |
                  product.lastServerSequence.isSmallerThanValue(
                    serverSequence,
                  )),
        ))
        .write(ProductsCompanion(lastServerSequence: Value(serverSequence)));
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

  Future<void> prepararActualizacionVariantes(
    String productId,
    Set<String> ids,
  ) async {
    final variants = (await obtenerVariantesPorProducto(
      productId,
    )).where((v) => ids.contains(v.id)).toList();
    final maxOrder = variants.fold<int>(
      0,
      (value, row) => row.sortOrder > value ? row.sortOrder : value,
    );
    for (var index = 0; index < variants.length; index++) {
      await (update(
        productVariants,
      )..where((v) => v.id.equals(variants[index].id))).write(
        ProductVariantsCompanion(
          name: const Value(null),
          nameKey: const Value(null),
          inventoryItemId: const Value(null),
          sortOrder: Value(maxOrder + index + 1),
        ),
      );
      await (delete(
        recipeComponents,
      )..where((c) => c.variantId.equals(variants[index].id))).go();
    }
  }

  Future<void> eliminarVariantesAgregadas(
    String productId,
    String eventId,
  ) async {
    await (delete(productVariants)..where(
          (v) =>
              v.productId.equals(productId) & v.createdEventId.equals(eventId),
        ))
        .go();
  }

  Future<void> actualizarVariante(
    String id,
    ProductVariantsCompanion values,
  ) async {
    await (update(
      productVariants,
    )..where((v) => v.id.equals(id))).write(values);
  }

  Future<void> guardarRespaldoActualizacion(
    String eventId,
    String productId,
  ) async {
    final product = await obtenerProductoPorId(productId);
    final variants = await obtenerVariantesPorProducto(productId);
    final recipes = <RecipeComponentRow>[];
    for (final v in variants) {
      recipes.addAll(await obtenerComponentesRecetaPorVariante(v.id));
    }
    await into(db.productUpdateUndo).insert(
      ProductUpdateUndoCompanion.insert(
        eventId: eventId,
        productId: productId,
        snapshotJson: jsonEncode({
          'product': product!.toJson(),
          'variants': variants.map((v) => v.toJson()).toList(),
          'recipes': recipes.map((r) => r.toJson()).toList(),
        }),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<bool> restaurarRespaldoActualizacion(
    String eventId,
    String baseEventId,
  ) async {
    final backup = await (select(
      db.productUpdateUndo,
    )..where((b) => b.eventId.equals(eventId))).getSingleOrNull();
    if (backup == null) return false;
    final current = await obtenerProductoPorId(backup.productId);
    if (current != null && current.lastEventId != eventId) {
      await (delete(
        db.productUpdateUndo,
      )..where((b) => b.eventId.equals(eventId))).go();
      return true;
    }
    final data = jsonDecode(backup.snapshotJson) as Map<String, dynamic>;
    final product = ProductRow.fromJson(
      Map<String, dynamic>.from(data['product'] as Map),
    );
    final base = await (select(
      db.events,
    )..where((e) => e.eventId.equals(baseEventId))).getSingleOrNull();
    final sequence = [
      product.lastServerSequence,
      current?.lastServerSequence,
      base?.serverSequence,
    ].whereType<int>().fold<int?>(null, (a, b) => a == null || b > a ? b : a);
    // El producto puede haber sido eliminado físicamente. Recuperar primero el padre.
    await into(products).insertOnConflictUpdate(
      product.copyWith(lastServerSequence: Value(sequence)),
    );
    final variants = (data['variants'] as List)
        .map(
          (v) =>
              ProductVariantRow.fromJson(Map<String, dynamic>.from(v as Map)),
        )
        .toList();
    final ids = variants.map((v) => v.id).toSet();
    final present = await obtenerVariantesPorProducto(product.id);
    await prepararActualizacionVariantes(
      product.id,
      present.map((v) => v.id).toSet(),
    );
    await (delete(
      productVariants,
    )..where((v) => v.productId.equals(product.id) & v.id.isNotIn(ids))).go();
    for (final v in variants) {
      await into(
        productVariants,
      ).insertOnConflictUpdate(v.copyWith(lastServerSequence: Value(sequence)));
    }
    for (final r in data['recipes'] as List) {
      await into(recipeComponents).insert(
        RecipeComponentRow.fromJson(Map<String, dynamic>.from(r as Map)),
      );
    }
    await (delete(
      db.productUpdateUndo,
    )..where((b) => b.eventId.equals(eventId))).go();
    return true;
  }

  Future<void> eliminarVarianteSinDependencias(String id) async {
    await (delete(productVariants)..where((v) => v.id.equals(id))).go();
  }

  Future<void> descartarRespaldosConfirmados(String productId) async {
    final confirmed = selectOnly(db.events)
      ..addColumns([db.events.eventId])
      ..where(
        db.events.aggregateId.equals(productId) &
            db.events.deliveryStatus.equals('delivered'),
      );
    await (delete(
      db.productUpdateUndo,
    )..where((b) => b.eventId.isInQuery(confirmed))).go();
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
