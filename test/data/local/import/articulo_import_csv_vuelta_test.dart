import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_store.dart';
import 'package:pos_flutter/application/export/articulo_catalog_export_service.dart';
import 'package:pos_flutter/application/import/articulo_catalog_import_service.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/export/drift_articulo_catalog_export_service.dart';
import 'package:pos_flutter/data/local/import/articulo_import_csv.dart';
import 'package:pos_flutter/domain/articulos/sale_mode.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/domain/inventario/unidad_inventario.dart';

/// El compositor y el validador comparten un solo contrato de columnas, y esto
/// lo comprueba de punta a punta: un catálogo exportado por la app tiene que
/// volver a entrar en el importador sin quejarse de nada.
///
/// El catálogo destino está vacío, como el de un dispositivo nuevo, porque
/// un artículo que ya existe en el destino se rechaza a propósito.
void main() {
  late AppDatabase db;
  late Directory tempDir;
  late DriftArticuloCatalogExportService exportador;
  const importador = ArticuloImportCsv();

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('catalogo_ida_vuelta');
    exportador = DriftArticuloCatalogExportService(
      productoDao: ProductoDao(db),
      configStore: _FakeConfigStore(),
      directorio: () async => tempDir,
      ahora: () => DateTime(2026, 10, 1),
    );
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: 'cat-bebidas',
            name: 'Bebidas',
            colorKey: const Value('blue'),
            sortOrder: 0,
          ),
        );
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<String> exportar() async {
    final archivo = await exportador.exportarCatalogo(
      ArticuloExportFiltro.sinFiltros,
    );
    return utf8.decode(await File(archivo.ruta).readAsBytes());
  }

  ArticuloImportReporte validar(String contenido) => importador.validar(
    contenido,
    catalogo: ArticuloImportCatalogo(
      categorias: const [
        ArticuloImportCategoria(id: 'cat-bebidas', nombre: 'Bebidas'),
      ],
      unidades: _unidades,
    ),
  );

  test(
    'la plantilla descargada contiene ejemplos válidos sin categorías',
    () async {
      final archivo = await exportador.exportarPlantilla();
      final contenido = utf8.decode(await File(archivo.ruta).readAsBytes());
      final reporte = importador.validar(
        contenido,
        catalogo: const ArticuloImportCatalogo(unidades: _unidades),
      );

      expect(reporte.errores, isEmpty);
      expect(reporte.importable, isTrue);
      expect(reporte.filasValidas, archivo.filas);
      expect(reporte.productos, hasLength(archivo.productos));
      expect(
        reporte.productos.every((producto) => producto.categoriaId == null),
        isTrue,
      );

      final cafe = reporte.productos[0];
      expect(cafe.modoVenta, SaleMode.unit);
      expect(cafe.variantes.single.seguimientoExistencias, isFalse);
      expect(cafe.variantes.single.precioCosteMinor, isNull);

      final agua = reporte.productos[1].variantes.single;
      expect(agua.seguimientoExistencias, isTrue);
      expect(agua.existenciasAtomic, 24);
      expect(agua.codigoBarras, '000000000001');

      final camiseta = reporte.productos[2];
      expect(camiseta.variantes.map((variante) => variante.nombre), [
        'Chica',
        'Grande',
      ]);

      final naranja = reporte.productos[3];
      expect(naranja.modoVenta, SaleMode.measured);
      expect(naranja.unidadVentaId, InventoryUnitIds.kilogram);
      expect(naranja.variantes.single.existenciasAtomic, 2500);
    },
  );

  test('un artículo por unidad vuelve a entrar con sus importes', () async {
    await _productoConVariantes(
      db,
      id: 'cafe',
      nombre: 'Café',
      categoryId: 'cat-bebidas',
      venta: 4550,
    );

    final reporte = validar(await exportar());

    expect(reporte.errores, isEmpty);
    final producto = reporte.productos.single;
    expect(producto.nombre, 'Café');
    expect(producto.categoriaId, 'cat-bebidas');
    expect(producto.modoVenta, SaleMode.unit);
    expect(producto.unidadVentaId, isNull);
    expect(producto.unidadInventarioId, InventoryUnitIds.piece);
    expect(producto.variantes.single.precioVentaMinor, 4550);
    expect(producto.variantes.single.precioCosteMinor, isNull);
    expect(producto.variantes.single.sortOrder, 0);
  });

  test('un artículo por fracción conserva unidad y variantes', () async {
    await _productoConVariantes(
      db,
      id: 'naranja',
      nombre: 'Naranja',
      categoryId: 'cat-bebidas',
      venta: 2500,
      ventaNombre: 'Sevillana',
      ventaCosto: 1500,
      ventaOrden: 1,
      unidadVentaId: InventoryUnitIds.kilogram,
    );
    await _variante(
      db,
      id: 'naranja-valencia',
      productId: 'naranja',
      nombre: 'Valencia',
      precio: 1800,
      costo: 1200,
      orden: 0,
    );

    final reporte = validar(await exportar());

    expect(reporte.errores, isEmpty);
    final producto = reporte.productos.single;
    expect(producto.modoVenta, SaleMode.measured);
    expect(producto.unidadVentaId, InventoryUnitIds.kilogram);
    // La cantidad de referencia la impone el factor atómico de la unidad, y la
    // unidad del recurso es la misma que la de venta (H8, H9).
    expect(producto.cantidadReferenciaPrecioAtomic, 1000);
    expect(producto.unidadInventarioId, InventoryUnitIds.kilogram);
    expect(producto.variantes.map((variante) => variante.nombre), [
      'Valencia',
      'Sevillana',
    ]);
    expect(producto.variantes.map((variante) => variante.sortOrder), [0, 1]);
    expect(producto.variantes.map((variante) => variante.precioVentaMinor), [
      1800,
      2500,
    ]);
    expect(producto.variantes.map((variante) => variante.precioCosteMinor), [
      1200,
      1500,
    ]);
  });

  test(
    'el archivo nunca lleva identidad y el importador no la espera',
    () async {
      await _productoConVariantes(
        db,
        id: 'cafe',
        nombre: 'Café',
        categoryId: 'cat-bebidas',
        venta: 4550,
      );

      final contenido = await exportar();

      for (final identidad in const [
        'product_id',
        'variant_id',
        'version',
        'last_event_id',
      ]) {
        expect(contenido, isNot(contains(identidad)));
      }
      expect(validar(contenido).errores, isEmpty);
    },
  );

  test('las líneas en blanco del archivo no cuentan como filas', () async {
    await _productoConVariantes(
      db,
      id: 'cafe',
      nombre: 'Café',
      categoryId: 'cat-bebidas',
      venta: 4550,
    );
    final exportado = await exportar();

    final reporte = validar(exportado.replaceAll('\n', '\n\n'));

    expect(reporte.errores, isEmpty);
    expect(reporte.productos, hasLength(1));
  });
}

/// Las 5 unidades que se siembran en cada dispositivo. Sus ids son los mismos
/// en todos, así que el round-trip no depende del equipo.
const _unidades = <UnidadInventario>[
  UnidadInventario(
    id: InventoryUnitIds.piece,
    code: 'piece',
    nombre: 'Pieza',
    simbolo: 'pza',
    dimension: DimensionUnidad.count,
    factorAtomico: 1,
    maximosDecimales: 0,
    activa: true,
  ),
  UnidadInventario(
    id: InventoryUnitIds.gram,
    code: 'g',
    nombre: 'Gramo',
    simbolo: 'g',
    dimension: DimensionUnidad.mass,
    factorAtomico: 1,
    maximosDecimales: 0,
    activa: true,
  ),
  UnidadInventario(
    id: InventoryUnitIds.kilogram,
    code: 'kg',
    nombre: 'Kilogramo',
    simbolo: 'kg',
    dimension: DimensionUnidad.mass,
    factorAtomico: 1000,
    maximosDecimales: 3,
    activa: true,
  ),
  UnidadInventario(
    id: InventoryUnitIds.milliliter,
    code: 'ml',
    nombre: 'Mililitro',
    simbolo: 'ml',
    dimension: DimensionUnidad.volume,
    factorAtomico: 1,
    maximosDecimales: 0,
    activa: true,
  ),
  UnidadInventario(
    id: InventoryUnitIds.liter,
    code: 'l',
    nombre: 'Litro',
    simbolo: 'L',
    dimension: DimensionUnidad.volume,
    factorAtomico: 1000,
    maximosDecimales: 3,
    activa: true,
  ),
];

Future<void> _productoConVariantes(
  AppDatabase db, {
  required String id,
  required String nombre,
  String? categoryId,
  required int venta,
  String? ventaNombre,
  int? ventaCosto,
  int ventaOrden = 0,
  String? unidadVentaId,
}) async {
  await db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          id: id,
          name: nombre,
          categoryId: Value(categoryId),
          saleMode: Value(unidadVentaId == null ? 'unit' : 'measured'),
          saleUnitId: Value(unidadVentaId),
          priceReferenceQuantityAtomic: Value(
            unidadVentaId == null ? null : 1000,
          ),
        ),
      );
  await _variante(
    db,
    id: 'variante-$id',
    productId: id,
    nombre: ventaNombre,
    precio: venta,
    costo: ventaCosto,
    orden: ventaOrden,
  );
}

Future<void> _variante(
  AppDatabase db, {
  required String id,
  required String productId,
  required int precio,
  int? costo,
  String? nombre,
  int orden = 0,
}) {
  return db
      .into(db.productVariants)
      .insert(
        ProductVariantsCompanion.insert(
          id: id,
          productId: productId,
          name: Value(nombre),
          nameKey: Value(nombre?.toLowerCase()),
          salePriceMinor: precio,
          standardCostMinor: Value(costo),
          sortOrder: orden,
        ),
      );
}

class _FakeConfigStore implements AppConfigStore {
  @override
  Future<AppConfig> readConfig() async => AppConfig.initial;

  @override
  Future<void> saveConfig(AppConfig config) async {}
}
