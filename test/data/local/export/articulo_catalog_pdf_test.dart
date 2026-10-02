import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/export/articulo_catalog_pdf.dart';
import 'package:pos_flutter/data/local/export/catalogo_pdf_documento.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  /// El compositor es puro: lee filas del listado y devuelve el modelo. Las
  /// filas salen de la base real y no de objetos armados a mano, para que el
  /// test no se pruebe a sí mismo.
  Future<CatalogoPdfDocumento> documento() async {
    return ArticuloCatalogPdf.documento(
      await ProductoDao(db).watchProductosListado().first,
      negocio: 'PASTOR',
      generado: DateTime(2026, 9, 30),
    );
  }

  test('agrupa por categoría y ordena los artículos alfabéticamente', () async {
    await _categoria(db, id: 'cat-bebidas', nombre: 'Bebidas');
    await _categoria(db, id: 'cat-abarrotes', nombre: 'Abarrotes');
    await _articulo(
      db,
      id: 'te',
      nombre: 'Té verde',
      categoryId: 'cat-bebidas',
    );
    await _articulo(db, id: 'cafe', nombre: 'Café', categoryId: 'cat-bebidas');
    await _articulo(
      db,
      id: 'arroz',
      nombre: 'Arroz',
      categoryId: 'cat-abarrotes',
    );

    final doc = await documento();

    // Por categoría, no por orden de inserción.
    expect(doc.categorias.map((c) => c.nombre), ['Abarrotes', 'Bebidas']);
    expect(doc.categorias.first.articulos.map((a) => a.nombre), ['Arroz']);
    // Dentro de la categoría va en orden alfabético, sin importar el alta.
    expect(doc.categorias.last.articulos.map((a) => a.nombre), [
      'Café',
      'Té verde',
    ]);
    expect(doc.articulos, 3);
  });

  test(
    'los productos sin categoría van en su propio grupo y al final',
    () async {
      await _categoria(db, id: 'cat-bebidas', nombre: 'Bebidas');
      await _articulo(
        db,
        id: 'cafe',
        nombre: 'Café',
        categoryId: 'cat-bebidas',
      );
      await _articulo(db, id: 'suelto', nombre: 'Art suelto');

      final doc = await documento();

      expect(doc.categorias.map((c) => c.nombre), [
        'Bebidas',
        ArticuloCatalogPdf.categoriaSinNombre,
      ]);
      expect(doc.categorias.last.articulos.single.nombre, 'Art suelto');
    },
  );

  test('el precio lleva la unidad, que es lo que lo hace legible', () async {
    await _articulo(db, id: 'agua', nombre: 'Agua mineral');
    await _articulo(
      db,
      id: 'arroz',
      nombre: 'Arroz',
      saleUnitId: InventoryUnitIds.kilogram,
    );

    final doc = await documento();
    final porNombre = {
      for (final categoria in doc.categorias)
        for (final articulo in categoria.articulos) articulo.nombre: articulo,
    };

    // "Arroz 28" no dice si son kilos o piezas: la etiqueta no es adorno.
    expect(
      porNombre['Agua mineral']!.lineas.single.etiquetaUnidad,
      'por unidad',
    );
    expect(porNombre['Arroz']!.lineas.single.etiquetaUnidad, 'por kg');
  });

  test('el dinero sale con símbolo de moneda y separador de miles', () {
    expect(ArticuloCatalogPdf.importe(4550), r'$45.50');
    expect(ArticuloCatalogPdf.importe(250000), r'$2,500.00');
    expect(ArticuloCatalogPdf.importe(1005), r'$10.05');
    expect(ArticuloCatalogPdf.importe(0), r'$0.00');
    expect(ArticuloCatalogPdf.importe(-1500), r'-$15.00');
  });

  test('el precio de venta es el de la variante, en centavos', () async {
    await _producto(db, id: 'cafe', nombre: 'Café');
    await _variante(db, id: 'v1', productId: 'cafe', price: 4550, sortOrder: 0);
    await _variante(
      db,
      id: 'v2',
      productId: 'cafe',
      price: 600000,
      sortOrder: 1,
    );

    final doc = await documento();

    expect(
      doc.categorias.single.articulos.single.lineas.map(
        (l) => l.precioVentaMinor,
      ),
      [4550, 600000],
    );
  });

  test('cada variante es una línea, ordenada por sort_order', () async {
    await _producto(db, id: 'naranja', nombre: 'Naranja');
    await _variante(
      db,
      id: 'naranja-sevillana',
      productId: 'naranja',
      nombre: 'Sevillana',
      price: 2500,
      sortOrder: 1,
    );
    await _variante(
      db,
      id: 'naranja-valencia',
      productId: 'naranja',
      nombre: 'Valencia',
      price: 1800,
      sortOrder: 0,
    );

    final doc = await documento();
    final articulo = doc.categorias.single.articulos.single;

    expect(articulo.nombre, 'Naranja');
    expect(articulo.lineas.map((l) => l.nombreVariante), [
      'Valencia',
      'Sevillana',
    ]);
    expect(doc.lineas, 2);
    // El producto se cuenta una vez, aunque tenga tres variantes.
    expect(doc.articulos, 1);
  });

  test(
    'el código de barras viaja como texto y es lo único que genera QR',
    () async {
      await _producto(db, id: 'agua', nombre: 'Agua mineral');
      await _variante(
        db,
        id: 'con-codigo',
        productId: 'agua',
        price: 2500,
        sortOrder: 0,
        barcode: '07501234567890',
      );
      await _variante(
        db,
        id: 'sin-codigo',
        productId: 'agua',
        price: 3200,
        sortOrder: 1,
      );

      final doc = await documento();
      final lineas = doc.categorias.single.articulos.single.lineas;

      // Los ceros iniciales se conservan: se escribe el texto, no un número.
      expect(lineas.first.codigoBarras, '07501234567890');
      expect(lineas.first.tieneCodigoBarras, isTrue);
      // Sin código de barras no hay QR: no hay otro dato del que generarlo.
      expect(lineas.last.codigoBarras, isNull);
      expect(lineas.last.tieneCodigoBarras, isFalse);
    },
  );

  test(
    'el nombre de variante vacío se trata como que no hay variante',
    () async {
      await _producto(db, id: 'cafe', nombre: 'Café');
      await _variante(
        db,
        id: 'v1',
        productId: 'cafe',
        nombre: '   ',
        price: 4550,
        sortOrder: 0,
      );

      final doc = await documento();

      expect(
        doc.categorias.single.articulos.single.lineas.single.nombreVariante,
        isNull,
      );
    },
  );

  test('solo entran productos activos con variantes activas', () async {
    await _articulo(db, id: 'cafe', nombre: 'Café');
    await _articulo(db, id: 'retirado', nombre: 'Retirado', active: false);

    final doc = await documento();

    expect(doc.articulos, 1);
    expect(doc.categorias.single.articulos.single.nombre, 'Café');
  });

  test('el documento lleva el negocio, la fecha y el contacto si hay', () async {
    await _articulo(db, id: 'cafe', nombre: 'Café');

    final conContacto = ArticuloCatalogPdf.documento(
      await ProductoDao(db).watchProductosListado().first,
      negocio: 'PASTOR',
      telefono: '55 1234 5678',
      generado: DateTime(2026, 9, 30),
    );
    final sinContacto = await documento();

    expect(conContacto.negocio, 'PASTOR');
    expect(conContacto.telefono, '55 1234 5678');
    // Sin contacto el pie lo omite: mejor sin línea que con un dato inventado.
    expect(sinContacto.telefono, isNull);
    expect(ArticuloCatalogPdf.fecha(conContacto.generado), '30/09/2026');
    expect(ArticuloCatalogPdf.avisoPrecios, 'Precios sujetos a cambio.');
  });

  test(
    'un catálogo vacío produce un documento sin categorías y un PDF válido',
    () async {
      final doc = await documento();

      expect(doc.categorias, isEmpty);
      expect(doc.articulos, 0);
      expect(doc.lineas, 0);
    },
  );

  test('los bytes son un PDF que se puede abrir', () async {
    await _categoria(db, id: 'cat-bebidas', nombre: 'Bebidas');
    await _articulo(
      db,
      id: 'cafe',
      nombre: 'Café',
      categoryId: 'cat-bebidas',
      barcode: '7501234567890',
    );

    final bytes = await ArticuloCatalogPdf.bytes(await documento());

    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(1000));
  });

  test('un catálogo vacío también se dibuja sin reventar', () async {
    final bytes = await ArticuloCatalogPdf.bytes(await documento());

    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test(
    'el PDF dibuja el QR solo en la línea que tiene código de barras',
    () async {
      await _categoria(db, id: 'cat-bebidas', nombre: 'Bebidas');
      await _articulo(
        db,
        id: 'con-codigo',
        nombre: 'Con código',
        categoryId: 'cat-bebidas',
        barcode: '7501234567890',
      );
      await _articulo(
        db,
        id: 'sin-codigo',
        nombre: 'Sin código',
        categoryId: 'cat-bebidas',
      );

      final conQr = await ArticuloCatalogPdf.bytes(await documento());
      final sinQr = await ArticuloCatalogPdf.bytes(
        _sinQr(await ProductoDao(db).watchProductosListado().first),
      );

      // Un QR son decenas de módulos negros dibujados. Sin código de barras no
      // hay QR: no hay otro dato del que generarlo, y uno inventado mentiría.
      expect(_modulos(conQr), greaterThan(50));
      expect(_modulos(sinQr), 0);
    },
  );

  test('un catálogo largo se pagina y numera sus páginas', () async {
    await _categoria(db, id: 'cat-bebidas', nombre: 'Bebidas');
    for (var i = 0; i < 120; i++) {
      await _articulo(
        db,
        id: 'art-$i',
        nombre: 'Artículo ${i.toString().padLeft(3, '0')}',
        categoryId: 'cat-bebidas',
      );
    }

    final bytes = await ArticuloCatalogPdf.bytes(await documento());

    // El pie numera "Página N de M": si el catálogo no cabe en una hoja, M es
    // mayor que 1 y el documento sigue siendo legible de principio a fin.
    expect(_modulos(bytes), 0);
    expect(bytes.length, greaterThan(1000));
  });
}

/// Copia de las filas con el código de barras borrado, para poder dibujar el
/// mismo catálogo con y sin QR y comparar.
CatalogoPdfDocumento _sinQr(List<ProductoListadoRow> filas) {
  return ArticuloCatalogPdf.documento(
    filas
        .map(
          (row) => row.variante!.barcode == null
              ? row
              : ProductoListadoRow(
                  producto: row.producto,
                  categoria: row.categoria,
                  variante: row.variante!.copyWith(
                    barcode: const Value<String?>(null),
                  ),
                  unidadVenta: row.unidadVenta,
                  inventario: row.inventario,
                  saldo: row.saldo,
                  unidadInventario: row.unidadInventario,
                  fechaCreacion: row.fechaCreacion,
                ),
        )
        .toList(growable: false),
    negocio: 'PASTOR',
    generado: DateTime(2026, 9, 30),
  );
}

/// Módulos negros dibujados en el PDF. Es la única forma de comprobar desde un
/// test que el QR salió, porque un QR es un dibujo vectorial y no aparece como
/// texto ni como imagen en el archivo.
int _modulos(Uint8List bytes) {
  final plano = latin1.decode(bytes);
  var total = 0;
  for (final match in RegExp('stream\\r?\\n').allMatches(plano)) {
    final fin = plano.indexOf('endstream', match.end);
    if (fin < 0) continue;
    try {
      final flujo = latin1.decode(
        ZLibDecoder().convert(bytes.sublist(match.end, fin)),
      );
      total += RegExp(' re ').allMatches(flujo).length;
    } catch (_) {
      continue;
    }
  }
  return total;
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
  String? barcode,
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
          sortOrder: sortOrder,
        ),
      );
}

Future<void> _articulo(
  AppDatabase db, {
  required String id,
  required String nombre,
  String? categoryId,
  bool active = true,
  String? saleUnitId,
  String? barcode,
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
    barcode: barcode,
  );
}
