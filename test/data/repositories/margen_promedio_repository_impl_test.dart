import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/margen_promedio_repository_impl.dart';

void main() {
  late AppDatabase db;
  late MargenPromedioRepositoryImpl repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = MargenPromedioRepositoryImpl(productoDao: db.productoDao);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'calcula margen por categoría promediando productos, no variantes',
    () async {
      await _categoria(db, 'c1');
      await _producto(db, 'p1', categoriaId: 'c1');
      await _variante(db, 'v1', productoId: 'p1', precio: 1000, costo: 500);
      await _variante(
        db,
        'v2',
        productoId: 'p1',
        precio: 2000,
        costo: 1000,
        sortOrder: 1,
      );
      await _producto(db, 'p2', categoriaId: 'c1');
      await _variante(db, 'v3', productoId: 'p2', precio: 1000, costo: 900);

      final margenes = await repository.watchMargenPromedioPorCategoria().first;

      // P1: (50 + 50) / 2 = 50. P2: 10. Categoría: (50 + 10) / 2 = 30.
      expect(margenes['c1'], closeTo(30, 0.0001));
    },
  );

  test(
    'excluye productos y variantes inactivos y agrupaciones sin datos',
    () async {
      await _categoria(db, 'c1');
      await _categoria(db, 'vacia');
      await _producto(db, 'activo', categoriaId: 'c1');
      await _variante(db, 'v1', productoId: 'activo', precio: 1000, costo: 500);
      await _producto(db, 'inactivo', categoriaId: 'c1', activo: false);
      await _variante(db, 'v2', productoId: 'inactivo', precio: 1000, costo: 0);
      await _producto(db, 'con-variante-inactiva', categoriaId: 'c1');
      await _variante(
        db,
        'v3',
        productoId: 'con-variante-inactiva',
        precio: 1000,
        costo: 0,
        activo: false,
      );

      final margenes = await repository.watchMargenPromedioPorCategoria().first;

      expect(margenes['c1'], closeTo(50, 0.0001));
      expect(margenes.containsKey('vacia'), isFalse);
    },
  );

  test(
    'excluye costo desconocido e incluye costo cero y margen negativo',
    () async {
      await _categoria(db, 'c1');
      await _producto(db, 'p1', categoriaId: 'c1');
      await _variante(db, 'sin-costo', productoId: 'p1', precio: 1000);
      await _variante(
        db,
        'costo-cero',
        productoId: 'p1',
        precio: 1000,
        costo: 0,
        sortOrder: 1,
      );
      await _variante(
        db,
        'negativo',
        productoId: 'p1',
        precio: 1000,
        costo: 1200,
        sortOrder: 2,
      );

      final margenes = await repository.watchMargenPromedioPorCategoria().first;

      // (100 + -20) / 2 = 40; la variante sin costo no participa.
      expect(margenes['c1'], closeTo(40, 0.0001));
    },
  );

  test(
    'usa el costo estándar de las variantes vinculadas a cada proveedor',
    () async {
      await _proveedor(db, 's1');
      await _proveedor(db, 's2');
      await _producto(db, 'p1');
      await _producto(db, 'p2');
      await _producto(db, 'p3', activo: false);
      await _variante(db, 'v1', productoId: 'p1', precio: 1000, costo: 500);
      await _variante(
        db,
        'v2',
        productoId: 'p1',
        precio: 1000,
        costo: 900,
        sortOrder: 1,
      );
      await _variante(db, 'v3', productoId: 'p2', precio: 1000, costo: 800);
      await _variante(
        db,
        'inactiva',
        productoId: 'p1',
        precio: 1000,
        costo: 0,
        activo: false,
        sortOrder: 2,
      );
      await _variante(db, 'v4', productoId: 'p3', precio: 1000, costo: 0);

      // Los precios informados son deliberadamente distintos: no son el costo.
      await _relacion(db, 'v1', 's1', precioInformado: 999999);
      await _relacion(db, 'v1', 's2', precioInformado: 1);
      await _relacion(db, 'v2', 's1', precioInformado: 1);
      await _relacion(db, 'v3', 's2', precioInformado: 0);
      await _relacion(db, 'inactiva', 's1', precioInformado: 1);
      await _relacion(db, 'v4', 's1', precioInformado: 1);

      final margenes = await repository.watchMargenPromedioPorProveedor().first;

      // S1, solo P1: ((50 + 10) / 2) = 30.
      // S2: P1 (v1) = 50 y P2 (v3) = 20; (50 + 20) / 2 = 35.
      expect(margenes['s1'], closeTo(30, 0.0001));
      expect(margenes['s2'], closeTo(35, 0.0001));
    },
  );

  test(
    'actualiza el margen al cambiar costo, categoría o estado activo',
    () async {
      await _categoria(db, 'c1');
      await _categoria(db, 'c2');
      await _producto(db, 'p1', categoriaId: 'c1');
      await _variante(db, 'v1', productoId: 'p1', precio: 1000, costo: 500);

      final iterator = StreamIterator(
        repository.watchMargenPromedioPorCategoria(),
      );
      addTearDown(iterator.cancel);

      await iterator.moveNext();
      expect(iterator.current['c1'], closeTo(50, 0.0001));

      await (db.update(db.productVariants)..where((v) => v.id.equals('v1')))
          .write(const ProductVariantsCompanion(standardCostMinor: Value(750)));
      await iterator.moveNext();
      expect(iterator.current['c1'], closeTo(25, 0.0001));

      await (db.update(db.products)..where((p) => p.id.equals('p1'))).write(
        const ProductsCompanion(categoryId: Value('c2')),
      );
      await iterator.moveNext();
      expect(iterator.current.containsKey('c1'), isFalse);
      expect(iterator.current['c2'], closeTo(25, 0.0001));

      await (db.update(db.products)..where((p) => p.id.equals('p1'))).write(
        const ProductsCompanion(active: Value(false)),
      );
      await iterator.moveNext();
      expect(iterator.current, isEmpty);
    },
  );

  test(
    'actualiza el margen al cambiar las relaciones con proveedores',
    () async {
      await _proveedor(db, 's1');
      await _producto(db, 'p1');
      await _variante(db, 'v1', productoId: 'p1', precio: 1000, costo: 500);
      await _variante(
        db,
        'v2',
        productoId: 'p1',
        precio: 1000,
        costo: 900,
        sortOrder: 1,
      );
      await _relacion(db, 'v1', 's1');

      final iterator = StreamIterator(
        repository.watchMargenPromedioPorProveedor(),
      );
      addTearDown(iterator.cancel);

      await iterator.moveNext();
      expect(iterator.current['s1'], closeTo(50, 0.0001));

      await _relacion(db, 'v2', 's1');
      await iterator.moveNext();
      expect(iterator.current['s1'], closeTo(30, 0.0001));

      await (db.delete(
        db.variantSuppliers,
      )..where((s) => s.variantId.equals('v2'))).go();
      await iterator.moveNext();
      expect(iterator.current['s1'], closeTo(50, 0.0001));
    },
  );
}

Future<void> _categoria(AppDatabase db, String id, {int sortOrder = 0}) {
  return db
      .into(db.categories)
      .insert(
        CategoriesCompanion.insert(id: id, name: id, sortOrder: sortOrder),
      );
}

Future<void> _proveedor(AppDatabase db, String id) {
  return db
      .into(db.suppliers)
      .insert(SuppliersCompanion.insert(id: id, name: id));
}

Future<void> _producto(
  AppDatabase db,
  String id, {
  String? categoriaId,
  bool activo = true,
}) {
  return db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          id: id,
          name: id,
          categoryId: Value(categoriaId),
          active: Value(activo),
        ),
      );
}

Future<void> _variante(
  AppDatabase db,
  String id, {
  required String productoId,
  required int precio,
  int? costo,
  bool activo = true,
  int sortOrder = 0,
}) {
  return db
      .into(db.productVariants)
      .insert(
        ProductVariantsCompanion.insert(
          id: id,
          productId: productoId,
          salePriceMinor: precio,
          standardCostMinor: Value(costo),
          active: Value(activo),
          sortOrder: sortOrder,
        ),
      );
}

Future<void> _relacion(
  AppDatabase db,
  String varianteId,
  String proveedorId, {
  int precioInformado = 1000,
}) {
  return db
      .into(db.variantSuppliers)
      .insert(
        VariantSuppliersCompanion.insert(
          variantId: varianteId,
          supplierId: proveedorId,
          quotedPriceMinor: precioInformado,
          quotedAtMs: 1,
        ),
      );
}
