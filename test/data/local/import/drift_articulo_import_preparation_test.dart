import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/import/articulo_csv_contract.dart';
import 'package:pos_flutter/application/import/articulo_import_preparation_service.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/import/articulo_import_csv.dart';
import 'package:pos_flutter/data/local/import/drift_articulo_import_catalog_reader.dart';

String _archivo(List<String> filas) =>
    '${ArticuloCsvContract.columnasConIdsAnteriores.join(',')}\n${filas.join('\n')}\n';
String _fila(
  String p,
  String v, {
  String nombre = 'Café',
  String variante = 'Chica',
  String precio = '25',
}) => '$p,$v,,$nombre,unidad,,$variante,$precio,,no,,00123';

void main() {
  late AppDatabase db;
  late _SqlAudit audit;
  late ArticuloImportPreparationService service;

  setUp(() async {
    audit = _SqlAudit();
    db = AppDatabase.forTesting(NativeDatabase.memory().interceptWith(audit));
    service = ArticuloImportPreparationService(
      parser: const ArticuloImportCsv(),
      reader: DriftArticuloImportCatalogReader(db),
    );
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'P',
            name: 'Café',
            createdEventId: const Value('created-P'),
            lastEventId: const Value('base-P'),
          ),
        );
    for (final (id, nombre, orden, activo) in [
      ('V', 'Chica', 0, true),
      ('W', 'Grande', 1, true),
      ('X', 'Retirada', 2, false),
    ]) {
      await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              id: id,
              productId: 'P',
              name: Value(nombre),
              nameKey: Value(nombre.toLowerCase()),
              barcode: const Value('00123'),
              salePriceMinor: 2500,
              sortOrder: orden,
              active: Value(activo),
              createdEventId: Value('created-$id'),
              lastEventId: const Value('base-P'),
            ),
          );
    }
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'Q',
            name: 'Inactivo',
            active: const Value(false),
          ),
        );
    await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            id: 'Q-V',
            productId: 'Q',
            salePriceMinor: 2500,
            sortOrder: 0,
          ),
        );
    audit.reset();
  });
  tearDown(() => db.close());

  Future<String> snapshot() async {
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
        )
        .get();
    return jsonEncode({
      for (final table in tables)
        table.read<String>(
          'name',
        ): (await db
                .customSelect('SELECT * FROM "${table.read<String>('name')}"')
                .get())
            .map((r) => r.data)
            .toList(),
    });
  }

  test(
    'C04 C13 C26 preparar iguales/cambios/errores no escribe ninguna tabla',
    () async {
      final before = await snapshot();
      for (final filas in [
        [_fila('P', 'V')],
        [_fila('P', 'V', precio: '26')],
        [_fila('P', 'V', variante: 'Grande')],
        [_fila('P', 'V'), _fila('P', 'W', variante: 'Grande', precio: 'error')],
      ]) {
        audit.reset();
        final report = await service.preparar(_archivo(filas));
        expect(audit.writes, 0);
        expect(audit.selects, hasLength(7));
        expect(
          audit.selects.any(
            (s) =>
                s.contains('inventory_balances') ||
                s.contains('product_update_undo'),
          ),
          isFalse,
        );
        if (report.productosConCambios.isNotEmpty) {
          final p = report.productosConCambios.single;
          expect(p.baseEventId, 'base-P');
          expect(p.actual.variantes.map((v) => v.id), ['V', 'W', 'X']);
          expect(p.actual.variantes.map((v) => v.sortOrder), [0, 1, 2]);
        }
        expect(await snapshot(), before);
      }
    },
  );
  test(
    'C08 C09 reader conserva actividad y pertenencia para rechazar',
    () async {
      for (final fila in [
        _fila('P', 'X'),
        _fila('Q', 'Q-V'),
        _fila('P', 'Q-V'),
        _fila('unknown', 'V'),
        _fila('P', 'unknown'),
      ]) {
        final r = await service.preparar(_archivo([fila]));
        expect(r.errores, isNotEmpty);
        expect(r.productos, isEmpty);
        expect(r.productosConCambios, isEmpty);
        expect(r.productosSinCambios, isEmpty);
      }
    },
  );
  test('C28 archivo estructuralmente inválido no consulta SQLite', () async {
    audit.reset();
    final r = await service.preparar('encabezado inválido\n');
    expect(r.erroresEstructurales, isTrue);
    expect(audit.selects, isEmpty);
    expect(audit.writes, 0);
  });
  test('CSV mixto o inconsistente no consulta ni escribe SQLite', () async {
    for (final fila in [
      'P;W;;Cafe;unidad;;;10;;no;;00123',
      'P,W,menos campos',
    ]) {
      audit.reset();
      final r = await service.preparar(_archivo([_fila('P', 'V'), fila]));
      expect(r.importable, isFalse);
      expect(r.productos, isEmpty);
      expect(r.productosConCambios, isEmpty);
      expect(audit.selects, isEmpty);
      expect(audit.writes, 0);
    }
  });
  test(
    '500 omitidos en catálogo de 10000: siete lecturas y cero escrituras',
    () async {
      await db.batch((b) {
        b.insertAll(db.products, [
          for (var i = 0; i < 9998; i++)
            ProductsCompanion.insert(
              id: 'p-$i',
              name: 'Producto $i',
              lastEventId: Value('base-$i'),
            ),
        ]);
        b.insertAll(db.productVariants, [
          for (var i = 0; i < 500; i++)
            ProductVariantsCompanion.insert(
              id: 'v-$i',
              productId: 'p-$i',
              salePriceMinor: 2500,
              sortOrder: 0,
              barcode: const Value('00123'),
            ),
        ]);
      });
      audit.reset();
      final r = await service.preparar(
        _archivo([
          for (var i = 0; i < 500; i++)
            _fila('p-$i', 'v-$i', nombre: 'Producto $i', variante: ''),
        ]),
      );
      expect(r.errores, isEmpty);
      expect(r.productosSinCambios, hasLength(500));
      expect(r.filasValidas, 500);
      expect(r.productosConCambios, isEmpty);
      expect(r.productos, isEmpty);
      expect(audit.writes, 0);
      expect(audit.selects, hasLength(7));
      expect(
        r.productosSinCambios.every((p) => p.actual.variantes.length == 1),
        isTrue,
      );
      final namesQuery = audit.selects.first;
      expect(namesQuery, contains('"name"'));
      expect(namesQuery, isNot(contains('SELECT *')));
    },
  );
  test(
    'clasificación mixta distingue cuatro conjuntos y productos de filas',
    () async {
      await db
          .into(db.products)
          .insert(ProductsCompanion.insert(id: 'R', name: 'Otro'));
      await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              id: 'R-V',
              productId: 'R',
              salePriceMinor: 2500,
              sortOrder: 0,
              barcode: const Value('00123'),
            ),
          );
      final r = await service.preparar(
        _archivo([
          _fila('P', 'V', precio: '26'),
          _fila('P', 'W', variante: 'Grande'),
          _fila('', '', nombre: 'Nuevo'),
          _fila('R', 'R-V', nombre: 'Otro', variante: ''),
          _fila('P', 'unknown'),
        ]),
      );
      // El error de identidad excluye todo P, sin afectar otros productos.
      expect(r.productosConCambios, isEmpty);
      expect(r.productos.single.nombre, 'Nuevo');
      expect(r.productosSinCambios.single.productId, 'R');
      expect(r.errores, isNotEmpty);
      final valido = await service.preparar(
        _archivo([
          _fila('P', 'V', precio: '26'),
          _fila('P', 'W', variante: 'Grande'),
          _fila('', '', nombre: 'Nuevo'),
          _fila('R', 'R-V', nombre: 'Otro', variante: ''),
          _fila('Q', 'Q-V'),
        ]),
      );
      expect(valido.productosConCambios, hasLength(1));
      expect(valido.filasConCambios, 2);
      expect(valido.productos, hasLength(1));
      expect(valido.filasNuevas, 1);
      expect(valido.productosSinCambios, hasLength(1));
      expect(valido.filasSinCambios, 1);
      expect(valido.filasValidas, 4);
      expect(valido.errores, isNotEmpty);
    },
  );
}

/// Auditoría de SQL real; no sustituye al adaptador ni intercepta resultados.
class _SqlAudit extends QueryInterceptor {
  final selects = <String>[];
  int writes = 0;
  void reset() {
    selects.clear();
    writes = 0;
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor e,
    String s,
    List<Object?> a,
  ) {
    selects.add(s);
    return super.runSelect(e, s, a);
  }

  @override
  Future<int> runInsert(QueryExecutor e, String s, List<Object?> a) {
    writes++;
    return super.runInsert(e, s, a);
  }

  @override
  Future<int> runUpdate(QueryExecutor e, String s, List<Object?> a) {
    writes++;
    return super.runUpdate(e, s, a);
  }

  @override
  Future<int> runDelete(QueryExecutor e, String s, List<Object?> a) {
    writes++;
    return super.runDelete(e, s, a);
  }

  @override
  Future<void> runCustom(QueryExecutor e, String s, List<Object?> a) {
    writes++;
    return super.runCustom(e, s, a);
  }

  @override
  Future<void> runBatched(QueryExecutor e, BatchedStatements s) {
    writes++;
    return super.runBatched(e, s);
  }
}
