import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_store.dart';
import 'package:pos_flutter/application/export/articulo_catalog_export_service.dart';
import 'package:pos_flutter/data/local/config/app_config_file_store.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/export/drift_articulo_catalog_export_service.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late DriftArticuloCatalogExportService service;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('catalogo_test');
    service = DriftArticuloCatalogExportService(
      productoDao: ProductoDao(db),
      configStore: _FakeConfigStore(),
      directorio: () async => tempDir,
      ahora: () => DateTime(2026, 9, 30),
    );
    for (final categoria in const [
      ('cat-bebidas', 'Bebidas'),
      ('cat-postres', 'Postres'),
    ]) {
      await _categoria(db, id: categoria.$1, nombre: categoria.$2);
    }
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  const encabezado =
      'categoria,nombre_articulo,tipo_venta,unidad_venta,nombre_variante,'
      'precio_venta,precio_coste,seguimiento_existencias,existencias,'
      'codigo_barras';

  Future<List<String>> leerLineas(String ruta) async {
    final bytes = await File(ruta).readAsBytes();
    return utf8
        .decode(bytes)
        .split('\n')
        .where((linea) => linea.isNotEmpty)
        .toList(growable: false);
  }

  test(
    'el catálogo sale con BOM, separado por comas y el encabezado del contrato',
    () async {
      await _articuloSinInventario(
        db,
        id: 'agua',
        nombre: 'Agua mineral',
        categoryId: 'cat-bebidas',
      );

      final archivo = await service.exportarCatalogo(
        ArticuloExportFiltro.sinFiltros,
      );

      final bytes = await File(archivo.ruta).readAsBytes();
      // BOM UTF-8: Excel y LibreOffice abren los acentos sin pedir nada.
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
      final texto = utf8.decode(bytes);
      // BOM UTF-8 se ha quitado al decodificar; el CSV empieza con el encabezado
      expect(texto.startsWith('$encabezado\n'), isTrue);
      expect(archivo.ruta.endsWith('catalogo_2026-09-30.csv'), isTrue);
    },
  );

  test(
    'escribe una fila por variante con las diez columnas del contrato',
    () async {
      await _articuloSinInventario(
        db,
        id: 'cafe',
        nombre: 'Café',
        categoryId: 'cat-bebidas',
      );

      final archivo = await service.exportarCatalogo(
        ArticuloExportFiltro.sinFiltros,
      );
      final lineas = await leerLineas(archivo.ruta);

      expect(lineas.first, encabezado);
      expect(lineas[1].split(','), [
        'Bebidas',
        'Café',
        'unidad',
        '',
        '',
        '45.50',
        '',
        'no',
        '0',
        '',
      ]);
      expect(archivo.productos, 1);
      expect(archivo.filas, 1);
    },
  );

  test(
    'agrupa las variantes de un producto y las ordena por sort_order',
    () async {
      await _productoConVariantes(
        db,
        id: 'naranja',
        nombre: 'Naranja',
        categoryId: 'cat-bebidas',
        saleUnitId: InventoryUnitIds.kilogram,
      );
      await _variante(
        db,
        id: 'naranja-sevillana',
        productId: 'naranja',
        nombre: 'Sevillana',
        price: 2500,
        standardCost: 1500,
        sortOrder: 1,
      );
      await _variante(
        db,
        id: 'naranja-valencia',
        productId: 'naranja',
        nombre: 'Valencia',
        price: 1800,
        standardCost: 1000,
        sortOrder: 0,
      );

      final archivo = await service.exportarCatalogo(
        ArticuloExportFiltro.sinFiltros,
      );
      final lineas = await leerLineas(archivo.ruta);

      expect(lineas, hasLength(3));
      // Valencia va antes que Sevillana aunque se insertara al revés.
      expect(lineas[1].split(',')[4], 'Valencia');
      expect(lineas[2].split(',')[4], 'Sevillana');
      expect(lineas[1].split(',')[0], 'Bebidas');
      expect(archivo.productos, 1);
      expect(archivo.filas, 2);
    },
  );

  test('la venta por fracción escribe la unidad de venta del código', () async {
    await _articuloSinInventario(
      db,
      id: 'naranja',
      nombre: 'Naranja',
      saleUnitId: InventoryUnitIds.kilogram,
    );

    final archivo = await service.exportarCatalogo(
      ArticuloExportFiltro.sinFiltros,
    );
    final campos = (await leerLineas(archivo.ruta))[1].split(',');

    expect(campos[2], 'fraccion');
    expect(campos[3], 'kg');
    expect(campos[1], 'Naranja');
  });

  test(
    'el dinero sale en decimales, con el costo vacío si se desconoce',
    () async {
      await _productoConVariantes(db, id: 'cafe', nombre: 'Café');
      await _variante(
        db,
        id: 'cafe-barato',
        productId: 'cafe',
        price: 1005,
        sortOrder: 0,
      );
      await _variante(
        db,
        id: 'cafe-caro',
        productId: 'cafe',
        price: 250000,
        standardCost: 0,
        sortOrder: 1,
      );

      final archivo = await service.exportarCatalogo(
        ArticuloExportFiltro.sinFiltros,
      );
      final lineas = await leerLineas(archivo.ruta);

      // 1005 centavos son 10.05, no 10.00: no se pierde el centavo.
      expect(lineas[1].split(',')[5], '10.05');
      expect(lineas[1].split(',')[6], '');
      expect(lineas[2].split(',')[5], '2500.00');
      // Costo cero es un costo conocido igual a cero, no vacío.
      expect(lineas[2].split(',')[6], '0.00');
    },
  );

  test(
    'con seguimiento escribe si y las existencias en la unidad del recurso',
    () async {
      await _productoConVariantes(db, id: 'arroz', nombre: 'Arroz');
      await _recurso(db, id: 'arroz-recurso', nombre: 'Arroz');
      await _saldo(db, recursoId: 'arroz-recurso', atomic: 120000);
      await _variante(
        db,
        id: 'arroz-unica',
        productId: 'arroz',
        price: 6000,
        standardCost: 4500,
        sortOrder: 0,
        inventarioId: 'arroz-recurso',
      );

      final archivo = await service.exportarCatalogo(
        ArticuloExportFiltro.sinFiltros,
      );
      final campos = (await leerLineas(archivo.ruta))[1].split(',');

      expect(campos[7], 'si');
      // 120000 átomos de un recurso en kg son 120 kg, no 120000.
      expect(campos[8], '120');
      expect(campos[9], '');
    },
  );

  test(
    'el código de barras se escribe como texto, con los ceros iniciales',
    () async {
      await _productoConVariantes(db, id: 'agua', nombre: 'Agua mineral');
      await _variante(
        db,
        id: 'agua-unica',
        productId: 'agua',
        price: 2500,
        standardCost: 1500,
        sortOrder: 0,
        barcode: '07501234567890',
      );

      final archivo = await service.exportarCatalogo(
        ArticuloExportFiltro.sinFiltros,
      );

      expect(
        (await leerLineas(archivo.ruta))[1].split(',')[9],
        '07501234567890',
      );
    },
  );

  test('sin categoría la columna queda vacía', () async {
    await _articuloSinInventario(db, id: 'suelto', nombre: 'Art suelto');

    final archivo = await service.exportarCatalogo(
      ArticuloExportFiltro.sinFiltros,
    );

    expect((await leerLineas(archivo.ruta))[1].split(',')[0], '');
  });

  test('exporta en mayúsculas el carácter que el listado normaliza', () async {
    await _articuloSinInventario(db, id: 'cafe', nombre: 'CAFÉ');

    final archivo = await service.exportarCatalogo(
      ArticuloExportFiltro.sinFiltros,
    );

    // Se escribe el nombre tal como está: el importador normaliza al leer.
    expect((await leerLineas(archivo.ruta))[1].split(',')[1], 'CAFÉ');
  });

  test('entrecomilla los valores con comas o comillas', () async {
    await _categoria(db, id: 'cat-punto', nombre: 'Panadería, Industrial');
    await _articuloSinInventario(
      db,
      id: 'pan',
      nombre: 'Pan "Integral"',
      categoryId: 'cat-punto',
    );

    final archivo = await service.exportarCatalogo(
      ArticuloExportFiltro.sinFiltros,
    );
    final lineas = await leerLineas(archivo.ruta);

    // Un valor con comillas también se entrecomilla, y las comillas internas se
    // duplican: es la forma de que un separador dentro del nombre no corra la fila.
    expect(
      lineas[1],
      '"Panadería, Industrial","Pan ""Integral""",unidad,,,45.50,,no,0,',
    );
  });

  test(
    'respeta los filtros de la pantalla y avisa cuántos de cuántos',
    () async {
      await _articuloSinInventario(
        db,
        id: 'cafe',
        nombre: 'Café',
        categoryId: 'cat-bebidas',
      );
      await _articuloSinInventario(
        db,
        id: 'te',
        nombre: 'Té',
        categoryId: 'cat-bebidas',
      );
      await _articuloSinInventario(
        db,
        id: 'pastel',
        nombre: 'Pastel',
        categoryId: 'cat-postres',
      );

      final archivo = await service.exportarCatalogo(
        const ArticuloExportFiltro(categoryIds: {'cat-bebidas'}),
      );
      final lineas = await leerLineas(archivo.ruta);

      expect(lineas, hasLength(3));
      expect(lineas.skip(1).map((linea) => linea.split(',')[1]), [
        'Café',
        'Té',
      ]);
      expect(archivo.productos, 2);
      expect(archivo.productosTotales, 3);
    },
  );

  test('el filtro de categoría con Sin categoría se combina con OR', () async {
    await _articuloSinInventario(
      db,
      id: 'cafe',
      nombre: 'Café',
      categoryId: 'cat-bebidas',
    );
    await _articuloSinInventario(db, id: 'suelto', nombre: 'Art suelto');

    final archivo = await service.exportarCatalogo(
      const ArticuloExportFiltro(
        categoryIds: {'cat-postres'},
        incluirSinCategoria: true,
      ),
    );

    // Solo el artículo sin categoría entra: Postres está vacía.
    expect(archivo.productos, 1);
    expect(archivo.productosTotales, 2);
  });

  test('sin filtros no lee el total y no lo reporta', () async {
    await _articuloSinInventario(db, id: 'cafe', nombre: 'Café');

    final archivo = await service.exportarCatalogo(
      ArticuloExportFiltro.sinFiltros,
    );

    expect(archivo.productosTotales, isNull);
    expect(archivo.productos, 1);
  });

  test('la búsqueda del catálogo también acota el archivo', () async {
    await _articuloSinInventario(db, id: 'cafe', nombre: 'Café');
    await _articuloSinInventario(db, id: 'pastel', nombre: 'Pastel');

    final archivo = await service.exportarCatalogo(
      const ArticuloExportFiltro(busqueda: 'pastel'),
    );
    final lineas = await leerLineas(archivo.ruta);

    expect(lineas, hasLength(2));
    expect(lineas[1].split(',')[1], 'Pastel');
    expect(archivo.productosTotales, 2);
  });

  test('solo exporta productos activos con variantes activas', () async {
    await _articuloSinInventario(db, id: 'cafe', nombre: 'Café');
    await _articuloSinInventario(
      db,
      id: 'retirado',
      nombre: 'Retirado',
      active: false,
    );

    final archivo = await service.exportarCatalogo(
      ArticuloExportFiltro.sinFiltros,
    );
    final lineas = await leerLineas(archivo.ruta);

    expect(lineas, hasLength(2));
    expect(lineas[1].split(',')[1], 'Café');
  });

  test('la plantilla trae el encabezado y ejemplos de llenado', () async {
    final archivo = await service.exportarPlantilla();

    expect(archivo.ruta.endsWith('plantilla_catalogo.csv'), isTrue);
    final lineas = await leerLineas(archivo.ruta);
    expect(lineas.first, encabezado);
    expect(lineas, hasLength(6));
    expect(
      lineas.skip(1).every((linea) => linea.startsWith(',Ejemplo - ')),
      isTrue,
    );
    expect(archivo.productos, 4);
    expect(archivo.filas, 5);
    expect(archivo.productosTotales, isNull);
  });

  test('las notas traen una fila por columna del contrato', () async {
    final archivo = await service.exportarNotasColumnas();

    expect(archivo.ruta.endsWith('catalogo_columnas.csv'), isTrue);
    final lineas = await leerLineas(archivo.ruta);
    expect(lineas.first, 'columna,obligatoria,valores_permitidos,descripcion');
    expect(lineas, hasLength(11));
    expect(lineas[1].split(',').first, 'categoria');
    expect(lineas.last.split(',').first, 'codigo_barras');
  });

  test(
    'el archivo no trae estado interno: ni id, ni version, ni event',
    () async {
      await _articuloSinInventario(db, id: 'cafe', nombre: 'Café');

      final archivo = await service.exportarCatalogo(
        ArticuloExportFiltro.sinFiltros,
      );
      final texto = (await File(archivo.ruta).readAsString()).toLowerCase();

      for (final prohibido in [
        'product_id',
        'variant_id',
        'last_event_id',
        'version',
        'activo',
        'active',
      ]) {
        expect(texto, isNot(contains(prohibido)));
      }
    },
  );

  group('el PDF', () {
    test('usa PASTOR aunque la configuración guardada diga Miradent', () async {
      await File(
        '${tempDir.path}/app_config.json',
      ).writeAsString(jsonEncode({'business_name': 'Miradent'}));
      await _articuloSinInventario(db, id: 'cafe', nombre: 'Café');
      final exportService = DriftArticuloCatalogExportService(
        productoDao: ProductoDao(db),
        configStore: AppConfigFileStore(directoryProvider: () async => tempDir),
        directorio: () async => tempDir,
        ahora: () => DateTime(2026, 9, 30),
      );

      final archivo = await exportService.exportarCatalogoPdf(
        ArticuloExportFiltro.sinFiltros,
      );
      final bytes = await File(archivo.ruta).readAsBytes();
      final plano = latin1.decode(bytes);
      final contenido = StringBuffer();
      for (final match in RegExp(r'\bstream\r?\n').allMatches(plano)) {
        final diccionario = plano.substring(
          plano.lastIndexOf('<<', match.start),
          match.start,
        );
        // El índice interno del PDF es un stream sin compresión ni texto.
        if (!diccionario.contains('/FlateDecode')) continue;
        final fin = plano.indexOf('endstream', match.end);
        if (fin < 0) continue;
        contenido.write(
          latin1.decode(ZLibDecoder().convert(bytes.sublist(match.end, fin))),
        );
      }

      // El nombre se dibuja tanto en el encabezado como en el pie de página.
      expect(RegExp('PASTOR').allMatches(contenido.toString()).length, 2);
      expect(contenido.toString(), isNot(contains('Miradent')));
      expect(plano, isNot(contains('Miradent')));
    });

    test('escribe un PDF con fecha y los mismos conteos que el CSV', () async {
      await _productoConVariantes(
        db,
        id: 'naranja',
        nombre: 'Naranja',
        categoryId: 'cat-bebidas',
      );
      await _variante(
        db,
        id: 'naranja-valencia',
        productId: 'naranja',
        nombre: 'Valencia',
        price: 1800,
        sortOrder: 0,
        barcode: '7501234567890',
      );
      await _variante(
        db,
        id: 'naranja-sevillana',
        productId: 'naranja',
        nombre: 'Sevillana',
        price: 2500,
        sortOrder: 1,
      );

      final pdf = await service.exportarCatalogoPdf(
        ArticuloExportFiltro.sinFiltros,
      );
      final csv = await service.exportarCatalogo(
        ArticuloExportFiltro.sinFiltros,
      );

      expect(pdf.ruta.endsWith('catalogo_2026-09-30.pdf'), isTrue);
      expect(
        String.fromCharCodes((await File(pdf.ruta).readAsBytes()).take(4)),
        '%PDF',
      );
      // El PDF y el CSV leen el mismo catálogo, así que no pueden discrepar.
      expect(pdf.productos, csv.productos);
      expect(pdf.filas, csv.filas);
      expect(pdf.productos, 1);
      expect(pdf.filas, 2);
    });

    test(
      'respeta los filtros de la pantalla y avisa cuántos de cuántos',
      () async {
        await _articuloSinInventario(
          db,
          id: 'cafe',
          nombre: 'Café',
          categoryId: 'cat-bebidas',
        );
        await _articuloSinInventario(
          db,
          id: 'pastel',
          nombre: 'Pastel',
          categoryId: 'cat-postres',
        );

        final pdf = await service.exportarCatalogoPdf(
          const ArticuloExportFiltro(categoryIds: {'cat-bebidas'}),
        );

        expect(pdf.productos, 1);
        expect(pdf.productosTotales, 2);
      },
    );

    test('sin filtros no lee el total y no lo reporta', () async {
      await _articuloSinInventario(db, id: 'cafe', nombre: 'Café');

      final pdf = await service.exportarCatalogoPdf(
        ArticuloExportFiltro.sinFiltros,
      );

      expect(pdf.productosTotales, isNull);
      expect(pdf.productos, 1);
    });

    test('un catálogo vacío también se escribe y se puede compartir', () async {
      final pdf = await service.exportarCatalogoPdf(
        ArticuloExportFiltro.sinFiltros,
      );

      expect(pdf.productos, 0);
      expect(pdf.filas, 0);
      expect(
        String.fromCharCodes((await File(pdf.ruta).readAsBytes()).take(4)),
        '%PDF',
      );
    });
  });
}

/// Configuración local fija: el PDF solo toma de aquí el nombre del negocio y
/// el teléfono del pie.
class _FakeConfigStore implements AppConfigStore {
  @override
  Future<AppConfig> readConfig() async =>
      AppConfig.initial.copyWith(businessName: 'PASTOR', businessPhone: null);

  @override
  Future<void> saveConfig(AppConfig config) async {}
}

Future<void> _categoria(
  AppDatabase db, {
  required String id,
  required String nombre,
}) {
  return db
      .into(db.categories)
      .insert(
        CategoriesCompanion.insert(
          id: id,
          name: nombre,
          colorKey: const Value('blue'),
          sortOrder: 0,
        ),
      );
}

Future<void> _producto(
  AppDatabase db, {
  required String id,
  required String nombre,
  String? categoryId,
  bool active = true,
  String? saleUnitId,
}) {
  final medido = saleUnitId != null;
  return db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          id: id,
          name: nombre,
          categoryId: Value(categoryId),
          saleMode: Value(medido ? 'measured' : 'unit'),
          saleUnitId: Value(saleUnitId),
          priceReferenceQuantityAtomic: Value(medido ? 1000 : null),
          active: Value(active),
        ),
      );
}

Future<void> _variante(
  AppDatabase db, {
  required String id,
  required String productId,
  required int price,
  required int sortOrder,
  String? nombre,
  int? standardCost,
  String? barcode,
  String? inventarioId,
}) {
  return db
      .into(db.productVariants)
      .insert(
        ProductVariantsCompanion.insert(
          id: id,
          productId: productId,
          name: Value(nombre),
          nameKey: Value(nombre?.toLowerCase()),
          barcode: Value(barcode),
          salePriceMinor: price,
          standardCostMinor: Value(standardCost),
          sortOrder: sortOrder,
          inventoryItemId: Value(inventarioId),
        ),
      );
}

Future<void> _recurso(
  AppDatabase db, {
  required String id,
  required String nombre,
  String defaultUnitId = InventoryUnitIds.kilogram,
}) {
  return db
      .into(db.inventoryItems)
      .insert(
        InventoryItemsCompanion.insert(
          id: id,
          name: nombre,
          defaultUnitId: defaultUnitId,
        ),
      );
}

Future<void> _saldo(
  AppDatabase db, {
  required String recursoId,
  required int atomic,
}) {
  return db
      .into(db.inventoryBalances)
      .insert(
        InventoryBalancesCompanion.insert(
          inventoryItemId: recursoId,
          quantityOnHandAtomic: atomic,
          quantityAvailableAtomic: atomic,
          lastEventId: 'seed',
        ),
      );
}

Future<void> _articuloSinInventario(
  AppDatabase db, {
  required String id,
  required String nombre,
  String? categoryId,
  bool active = true,
  String? saleUnitId,
}) async {
  await _producto(
    db,
    id: id,
    nombre: nombre,
    categoryId: categoryId,
    active: active,
    saleUnitId: saleUnitId,
  );
  await _variante(
    db,
    id: 'variante-$id',
    productId: id,
    price: 4550,
    sortOrder: 0,
  );
}

Future<void> _productoConVariantes(
  AppDatabase db, {
  required String id,
  required String nombre,
  String? categoryId,
  String? saleUnitId,
}) {
  return _producto(
    db,
    id: id,
    nombre: nombre,
    categoryId: categoryId,
    saleUnitId: saleUnitId,
  );
}
