import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/producto_repository_impl.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';

void main() {
  late Directory temp;
  late AppDatabase db;
  late ProductoRepositoryImpl repository;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('barcode-query-');
    db = AppDatabase.forTesting(
      NativeDatabase(File('${temp.path}/catalog.sqlite')),
    );
    repository = ProductoRepositoryImpl(productoDao: db.productoDao);
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<void> product(
    String id, {
    bool active = true,
    bool measured = false,
  }) => db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          id: id,
          name: id,
          active: Value(active),
          saleMode: Value(measured ? 'measured' : 'unit'),
          saleUnitId: Value(measured ? InventoryUnitIds.kilogram : null),
          priceReferenceQuantityAtomic: Value(measured ? 1000 : null),
        ),
      );
  Future<void> variant(
    String id,
    String productId,
    String? barcode, {
    bool active = true,
    int order = 0,
    String? name,
  }) => db
      .into(db.productVariants)
      .insert(
        ProductVariantsCompanion.insert(
          id: id,
          productId: productId,
          name: Value(name),
          nameKey: Value(name?.toLowerCase()),
          barcode: Value(barcode),
          active: Value(active),
          salePriceMinor: 12345,
          sortOrder: order,
        ),
      );

  test(
    'cero/uno: igualdad exacta, NFKC y ceros conservados; consulta sin eventos',
    () async {
      await product('Café');
      await variant('coffee', 'Café', '012345678905');
      await variant('without-zero', 'Café', '12345678905', order: 1);
      await variant('no-barcode', 'Café', null, order: 2);
      expect(await repository.buscarVariantesPorCodigoBarras(''), isEmpty);
      expect(await repository.buscarVariantesPorCodigoBarras('   '), isEmpty);
      expect(
        await repository.buscarVariantesPorCodigoBarras('01234567890'),
        isEmpty,
      );
      expect(
        await repository.buscarVariantesPorCodigoBarras('99999999'),
        isEmpty,
      );
      final candidate = (await repository.buscarVariantesPorCodigoBarras(
        ' ０１２３４５６７８９０５ ',
      )).single;
      expect(candidate.productoId, 'Café');
      expect(candidate.varianteId, 'coffee');
      expect(candidate.nombreProducto, 'Café');
      expect(candidate.nombreVariante, isNull);
      expect(candidate.codigoBarras, '012345678905');
      expect(candidate.precioVentaMenor, 12345);
      expect(candidate.saleConfiguration, const UnitSaleConfiguration());
      expect(candidate.unidadVenta, isNull);
      expect(
        (await repository.buscarVariantesPorCodigoBarras(
          '12345678905',
        )).single.varianteId,
        'without-zero',
      );
      for (final invalid in ['ABC', '12-34', '123%', '0' * 33]) {
        await expectLater(
          repository.buscarVariantesPorCodigoBarras(invalid),
          throwsArgumentError,
        );
      }
      expect(await db.select(db.events).get(), isEmpty);
      expect(await db.select(db.eventRefs).get(), isEmpty);
      expect(await db.select(db.sales).get(), isEmpty);
    },
  );

  test(
    'varios: devuelve todos los activos de varios productos, ordenados',
    () async {
      await product('A');
      await product('B');
      await product('Hidden', active: false);
      await variant('a1', 'A', '000001', name: 'Chico', order: 1);
      await variant('a0', 'A', '000001', name: 'Grande');
      await variant('b', 'B', '000001');
      await variant('inactive', 'A', '000001', active: false, order: 2);
      await variant('inactive-product', 'Hidden', '000001');
      final candidates = await repository.buscarVariantesPorCodigoBarras(
        '000001',
      );
      expect(candidates.map((c) => c.varianteId), ['a0', 'a1', 'b']);
      expect(candidates.map((c) => c.nombreVariante), [
        'Grande',
        'Chico',
        null,
      ]);
      expect(candidates.map((c) => c.productoId), ['A', 'A', 'B']);
      await db.productoDao.actualizarProducto(
        'A',
        const ProductsCompanion(active: Value(false)),
      );
      await db.productoDao.actualizarProducto(
        'B',
        const ProductsCompanion(active: Value(false)),
      );
      expect(
        await repository.buscarVariantesPorCodigoBarras('000001'),
        isEmpty,
      );
    },
  );

  test(
    'venta medida incluye configuración y todos los datos de la unidad',
    () async {
      await product('Medido', measured: true);
      await variant('kg', 'Medido', '000002');
      // La disponibilidad se revalida al agregar; buscar no oculta un producto
      // activo por el estado de su unidad.
      await (db.update(db.units)
            ..where((u) => u.unitId.equals(InventoryUnitIds.kilogram)))
          .write(const UnitsCompanion(active: Value(false)));
      final candidate = (await repository.buscarVariantesPorCodigoBarras(
        '000002',
      )).single;
      expect(
        candidate.saleConfiguration,
        MeasuredSaleConfiguration(
          saleUnitId: InventoryUnitIds.kilogram,
          priceReferenceQuantityAtomic: 1000,
        ),
      );
      final unit = candidate.unidadVenta!;
      expect(unit.id, InventoryUnitIds.kilogram);
      expect(unit.code, 'kg');
      expect(unit.nombre, 'Kilogramo');
      expect(unit.simbolo, 'kg');
      expect(unit.dimension, DimensionUnidad.mass);
      expect(unit.factorAtomico, 1000);
      expect(unit.maximosDecimales, 3);
      expect(unit.activa, isFalse);
    },
  );
}
