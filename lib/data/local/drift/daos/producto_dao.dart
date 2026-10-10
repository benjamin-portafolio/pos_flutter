part of '../app_database.dart';

@DriftAccessor(
  tables: [Products, ProductVariants, RecipeComponents, VariantSuppliers],
)
class ProductoDao extends DatabaseAccessor<AppDatabase>
    with _$ProductoDaoMixin {
  ProductoDao(super.db);

  /// Igualdad textual sobre el código ya normalizado, sin cargar el catálogo.
  Future<List<ProductoCodigoBarrasRow>> buscarVariantesPorCodigoBarras(
    String codigo,
  ) async {
    final query =
        select(productVariants).join([
          innerJoin(products, products.id.equalsExp(productVariants.productId)),
          leftOuterJoin(
            db.units,
            db.units.unitId.equalsExp(products.saleUnitId),
          ),
        ])..where(
          productVariants.barcode.equals(codigo) &
              productVariants.active.equals(true) &
              products.active.equals(true),
        );
    query.orderBy([
      OrderingTerm(expression: products.name.lower()),
      OrderingTerm(expression: products.id),
      OrderingTerm(expression: productVariants.sortOrder),
      OrderingTerm(expression: productVariants.id),
    ]);
    return (await query.get())
        .map(
          (row) => ProductoCodigoBarrasRow(
            producto: row.readTable(products),
            variante: row.readTable(productVariants),
            unidadVenta: row.readTableOrNull(db.units),
          ),
        )
        .toList(growable: false);
  }

  Stream<List<ProductoListadoRow>> watchProductosListado({
    String busqueda = '',
    Set<String> categoriaIds = const <String>{},
    bool incluirSinCategoria = false,
  }) {
    final saleUnit = alias(db.units, 'sale_unit');
    final inventoryUnit = alias(db.units, 'inventory_unit');
    final query = select(products).join([
      leftOuterJoin(
        db.events,
        db.events.eventId.equalsExp(products.createdEventId),
        useColumns: false,
      ),
      leftOuterJoin(categories, categories.id.equalsExp(products.categoryId)),
      leftOuterJoin(
        productVariants,
        productVariants.productId.equalsExp(products.id) &
            productVariants.active.equals(true),
      ),
      leftOuterJoin(saleUnit, saleUnit.unitId.equalsExp(products.saleUnitId)),
      leftOuterJoin(
        db.inventoryItems,
        db.inventoryItems.id.equalsExp(productVariants.inventoryItemId),
      ),
      leftOuterJoin(
        db.inventoryBalances,
        db.inventoryBalances.inventoryItemId.equalsExp(
          productVariants.inventoryItemId,
        ),
      ),
      leftOuterJoin(
        inventoryUnit,
        inventoryUnit.unitId.equalsExp(db.inventoryItems.defaultUnitId),
      ),
    ])..where(products.active.equals(true));
    query.addColumns([db.events.createdAtLocal]);

    final normalizedSearch = busqueda.trim().toLowerCase();
    if (normalizedSearch.isNotEmpty) {
      final pattern = '%${_escapeLike(normalizedSearch)}%';
      final matchingProducts = selectOnly(productVariants)
        ..addColumns([productVariants.productId])
        ..where(
          productVariants.active.equals(true) &
              productVariants.name.lower().like(pattern, escapeChar: r'\'),
        );
      query.where(
        products.name.lower().like(pattern, escapeChar: r'\') |
            products.id.isInQuery(matchingProducts),
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
              unidadVenta: row.readTableOrNull(saleUnit),
              inventario: row.readTableOrNull(db.inventoryItems),
              saldo: row.readTableOrNull(db.inventoryBalances),
              unidadInventario: row.readTableOrNull(inventoryUnit),
              fechaCreacion: row.read(db.events.createdAtLocal),
            ),
          )
          .toList(growable: false),
    );
  }

  /// Variantes activas que pertenecen a productos activos. Alimenta el contador
  /// del menú lateral, que solo debe reflejar el catálogo vendible.
  Stream<int> watchVariantesActivasCount() {
    final count = productVariants.id.count();
    final activeProducts = selectOnly(products)
      ..addColumns([products.id])
      ..where(products.active.equals(true));
    final query = selectOnly(productVariants)
      ..addColumns([count])
      ..where(
        productVariants.active.equals(true) &
            productVariants.productId.isInQuery(activeProducts),
      );
    return query.watchSingle().map((row) => row.read(count) ?? 0);
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

  /// Variantes que mantienen vínculo directo con un recurso, incluidas las
  /// inactivas. La unicidad normativa del vínculo directo cuenta también las
  /// filas retiradas: una variante inactiva sigue reservando el recurso.
  Future<List<ProductVariantRow>> obtenerVariantesPorRecurso(
    String inventoryItemId,
  ) {
    return (select(productVariants)
          ..where((variant) => variant.inventoryItemId.equals(inventoryItemId)))
        .get();
  }

  /// Variantes que consumen un recurso como componente de receta, incluidas las
  /// inactivas. El uso en receta no impide recuperar el recurso: sigue siendo un
  /// recurso compartido.
  Future<List<ProductVariantRow>> obtenerVariantesConRecetaDeRecurso(
    String inventoryItemId,
  ) {
    final componentes = selectOnly(recipeComponents)
      ..addColumns([recipeComponents.variantId])
      ..where(recipeComponents.inventoryItemId.equals(inventoryItemId));
    return (select(
      productVariants,
    )..where((variant) => variant.id.isInQuery(componentes))).get();
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

  Future<List<VariantSupplierRow>> obtenerProveedoresPorVariante(
    String variantId,
  ) =>
      (select(variantSuppliers)
            ..where((s) => s.variantId.equals(variantId))
            ..orderBy([(s) => OrderingTerm(expression: s.supplierId)]))
          .get();

  Future<void> reemplazarProveedoresVariante(
    String variantId,
    List<VariantSuppliersCompanion> values,
  ) async {
    await (delete(
      variantSuppliers,
    )..where((s) => s.variantId.equals(variantId))).go();
    for (final value in values) {
      await into(variantSuppliers).insert(value);
    }
  }

  /// Conocimiento del campo declarado en snapshots registrados del producto.
  /// También before conserva este conocimiento al restaurar una base legada;
  /// un evento revertido no vuelve a convertir un conjunto conocido en ausencia.
  /// Una transacción fallida no deja bitácora ni acredita conocimiento.
  Future<List<EventRecord>> eventosEstadoProveedores(
    String productId, {
    required String aggregateType,
  }) =>
      (select(db.events)..where(
            (e) =>
                e.aggregateType.equals(aggregateType) &
                e.aggregateId.equals(productId),
          ))
          .get();

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

  /// Se conservan identidades para cobros offline aún desconocidos.
  Future<void> desactivarProductoHistorico(
    String id,
    String eventId,
    int version,
    int? sequence,
  ) async {
    await (update(productVariants)..where((v) => v.productId.equals(id))).write(
      ProductVariantsCompanion(
        active: const Value(false),
        version: Value(version),
        lastEventId: Value(eventId),
        lastServerSequence: Value(sequence),
      ),
    );
    await (update(products)..where((p) => p.id.equals(id))).write(
      ProductsCompanion(
        active: const Value(false),
        version: Value(version),
        lastEventId: Value(eventId),
        lastServerSequence: Value(sequence),
      ),
    );
  }

  Future<void> eliminarProductoPorId(String id) async {
    await (delete(
      productVariants,
    )..where((variant) => variant.productId.equals(id))).go();
    await (delete(products)..where((product) => product.id.equals(id))).go();
  }

  Future<void> eliminarProductoCreadoPorEvento(String eventId) async {
    final variants = await (select(
      productVariants,
    )..where((v) => v.createdEventId.equals(eventId))).get();
    for (final v in variants) {
      if (await (select(db.saleItems)
                ..where((l) => l.variantId.equals(v.id))
                ..limit(1))
              .getSingleOrNull() !=
          null) {
        await (update(
          products,
        )..where((p) => p.createdEventId.equals(eventId))).write(
          const ProductsCompanion(
            active: Value(false),
            categoryId: Value(null),
          ),
        );
        await (update(productVariants)
              ..where((p) => p.createdEventId.equals(eventId)))
            .write(const ProductVariantsCompanion(active: Value(false)));
        return;
      }
    }
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
    final added =
        await (select(productVariants)..where(
              (v) =>
                  v.productId.equals(productId) &
                  v.createdEventId.equals(eventId),
            ))
            .get();
    for (final variant in added) {
      await _removeUnreferencedVariant(variant.id);
    }
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
    final suppliers = <VariantSupplierRow>[];
    for (final v in variants) {
      recipes.addAll(await obtenerComponentesRecetaPorVariante(v.id));
      suppliers.addAll(await obtenerProveedoresPorVariante(v.id));
    }
    final memories =
        await (select(db.variantInventoryMemory)..where(
              (m) => m.variantId.isIn(variants.map((v) => v.id).toList()),
            ))
            .get();
    await into(db.productUpdateUndo).insert(
      ProductUpdateUndoCompanion.insert(
        eventId: eventId,
        productId: productId,
        snapshotJson: jsonEncode({
          'product': product!.toJson(),
          'variants': variants.map((v) => v.toJson()).toList(),
          'recipes': recipes.map((r) => r.toJson()).toList(),
          'suppliers': suppliers.map((s) => s.toJson()).toList(),
        }),
        memoryJson: Value(
          jsonEncode(
            memories
                .map(
                  (m) => {
                    'variant_id': m.variantId,
                    'inventory_item_id': m.inventoryItemId,
                    'source_event_id': m.sourceEventId,
                    'source_server_sequence': m.sourceServerSequence,
                  },
                )
                .toList(),
          ),
        ),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<bool> restaurarRespaldoActualizacion(
    String eventId,
    String baseEventId,
  ) => db.transaction(
    () => _restaurarRespaldoActualizacion(eventId, baseEventId),
  );

  Future<bool> _restaurarRespaldoActualizacion(
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
      // Las secuencias de rechazos/conflictos no acreditan una base oficial.
      if (base?.deliveryStatus == 'delivered') base?.serverSequence,
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
    for (final v in present.where((v) => !ids.contains(v.id))) {
      await _removeUnreferencedVariant(v.id);
    }
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
    // Un respaldo anterior desconoce el campo: nunca autoriza borrar relaciones.
    if (data.containsKey('suppliers')) {
      for (final id in ids) {
        await reemplazarProveedoresVariante(id, const []);
      }
      for (final s in data['suppliers'] as List) {
        await into(variantSuppliers).insert(
          VariantSupplierRow.fromJson(Map<String, dynamic>.from(s as Map)),
        );
      }
    }
    // Restaurar también la ausencia previa, sin ocultar fallos de integridad.
    final affectedIds = {...ids, ...present.map((v) => v.id)};
    await (delete(
      db.variantInventoryMemory,
    )..where((m) => m.variantId.isIn(affectedIds.toList()))).go();
    {
      final memoryData = jsonDecode(backup.memoryJson) as List;
      for (final m in memoryData) {
        await into(db.variantInventoryMemory).insertOnConflictUpdate(
          VariantInventoryMemoryCompanion.insert(
            variantId: m['variant_id'] as String,
            inventoryItemId: m['inventory_item_id'] as String,
            sourceEventId: m['source_event_id'] as String,
            sourceServerSequence: Value<int?>(
              m['source_server_sequence'] as int?,
            ),
          ),
        );
      }
    }
    await (delete(
      db.productUpdateUndo,
    )..where((b) => b.eventId.equals(eventId))).go();
    return true;
  }

  Future<void> _removeUnreferencedVariant(String id) async {
    final referenced =
        await (select(db.saleItems)
              ..where((l) => l.variantId.equals(id))
              ..limit(1))
            .getSingleOrNull();
    if (referenced != null) {
      await (update(productVariants)..where((v) => v.id.equals(id))).write(
        const ProductVariantsCompanion(active: Value(false)),
      );
    } else {
      await (delete(productVariants)..where((v) => v.id.equals(id))).go();
    }
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
