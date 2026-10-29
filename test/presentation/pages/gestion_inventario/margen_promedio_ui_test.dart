import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/categoria_repository_impl.dart';
import 'package:pos_flutter/data/repositories/margen_promedio_repository_impl.dart';
import 'package:pos_flutter/data/repositories/proveedor_repository_impl.dart';
import 'package:pos_flutter/domain/repositories/margen_promedio_repository.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/categorias/inventory_categories_tab.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/proveedores/inventory_suppliers_tab.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  void uiTest(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    });
  }

  uiTest('la tarjeta de categoría refleja cambios locales de costo', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await _categoria(db, 'c1');
      await _producto(db, 'p1', categoriaId: 'c1');
      await _variante(db, 'v1', productoId: 'p1', precio: 1000, costo: 675);
    });

    var deletes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventoryCategoriesTab(
            categoriaRepository: CategoriaRepositoryImpl(
              categoriaDao: db.categoriaDao,
            ),
            margenPromedioRepository: MargenPromedioRepositoryImpl(
              productoDao: db.productoDao,
            ),
            onEditCategory: (_) {},
            onMoveCategory: (_, _) {},
            onDeleteCategory: (_) => deletes++,
          ),
        ),
      ),
    );

    await _esperarTexto(tester, 'Margen promedio: 32.5 %');
    expect(find.text('c1'), findsOneWidget);
    expect(find.byKey(const Key('delete_category_button')), findsOneWidget);

    await tester.runAsync(
      () => (db.update(db.productVariants)..where((v) => v.id.equals('v1')))
          .write(const ProductVariantsCompanion(standardCostMinor: Value(600))),
    );

    await _esperarTexto(tester, 'Margen promedio: 40.0 %');
    expect(find.text('Margen promedio: 32.5 %'), findsNothing);

    await tester.tap(find.byKey(const Key('delete_category_button')));
    expect(deletes, 1);
  });

  uiTest('la tarjeta de proveedor refleja cambios de relación y costo', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await _proveedor(db, 's1');
      await _producto(db, 'p1');
      await _variante(db, 'v1', productoId: 'p1', precio: 1000, costo: 675);
    });

    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventorySuppliersTab(
            repository: ProveedorRepositoryImpl(db.proveedorDao),
            margenPromedioRepository: MargenPromedioRepositoryImpl(
              productoDao: db.productoDao,
            ),
            onOpen: (_) => opens++,
            onAdd: () {},
          ),
        ),
      ),
    );

    await _esperarTexto(tester, 'Margen promedio: Sin datos');

    await tester.runAsync(() => _relacion(db, 'v1', 's1'));
    await _esperarTexto(tester, 'Margen promedio: 32.5 %');

    await tester.runAsync(
      () => (db.update(db.productVariants)..where((v) => v.id.equals('v1')))
          .write(const ProductVariantsCompanion(standardCostMinor: Value(600))),
    );
    await _esperarTexto(tester, 'Margen promedio: 40.0 %');

    await tester.tap(find.byKey(const Key('supplier_s1')));
    expect(opens, 1);
  });

  uiTest('la pestaña distingue carga, error y datos posteriores', (
    tester,
  ) async {
    await tester.runAsync(() => _categoria(db, 'c1'));
    final margenes = StreamController<Map<String, double>>();
    addTearDown(margenes.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventoryCategoriesTab(
            categoriaRepository: CategoriaRepositoryImpl(
              categoriaDao: db.categoriaDao,
            ),
            margenPromedioRepository: _StreamMargenes(margenes.stream),
            onEditCategory: (_) {},
            onMoveCategory: (_, _) {},
            onDeleteCategory: (_) {},
          ),
        ),
      ),
    );

    await _esperarTexto(tester, 'Margen promedio: Cargando...');

    margenes.addError(StateError('fallo de lectura'));
    await tester.pumpAndSettle();
    expect(find.text('Margen promedio: No disponible'), findsOneWidget);
    expect(find.text('Margen promedio: Sin datos'), findsNothing);

    margenes.add(const {'c1': 12.34});
    await tester.pumpAndSettle();
    expect(find.text('Margen promedio: 12.3 %'), findsOneWidget);
  });
}

Future<void> _esperarTexto(WidgetTester tester, String texto) async {
  for (var intento = 0; intento < 100; intento++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
    if (find.text(texto).evaluate().isNotEmpty) return;
  }
  fail('No apareció el texto: $texto');
}

Future<void> _categoria(AppDatabase db, String id) {
  return db
      .into(db.categories)
      .insert(CategoriesCompanion.insert(id: id, name: id, sortOrder: 0));
}

Future<void> _proveedor(AppDatabase db, String id) {
  return db
      .into(db.suppliers)
      .insert(SuppliersCompanion.insert(id: id, name: id));
}

Future<void> _producto(AppDatabase db, String id, {String? categoriaId}) {
  return db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          id: id,
          name: id,
          categoryId: Value(categoriaId),
        ),
      );
}

Future<void> _variante(
  AppDatabase db,
  String id, {
  required String productoId,
  required int precio,
  int? costo,
}) {
  return db
      .into(db.productVariants)
      .insert(
        ProductVariantsCompanion.insert(
          id: id,
          productId: productoId,
          salePriceMinor: precio,
          standardCostMinor: Value(costo),
          sortOrder: 0,
        ),
      );
}

Future<void> _relacion(AppDatabase db, String varianteId, String proveedorId) {
  return db
      .into(db.variantSuppliers)
      .insert(
        VariantSuppliersCompanion.insert(
          variantId: varianteId,
          supplierId: proveedorId,
          quotedPriceMinor: 1,
          quotedAtMs: 1,
        ),
      );
}

class _StreamMargenes implements MargenPromedioRepository {
  const _StreamMargenes(this.stream);

  final Stream<Map<String, double>> stream;

  @override
  Stream<Map<String, double>> watchMargenPromedioPorCategoria() => stream;

  @override
  Stream<Map<String, double>> watchMargenPromedioPorProveedor() => stream;
}
