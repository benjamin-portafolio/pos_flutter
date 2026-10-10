import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_proveedor_precio.dart';
import 'package:pos_flutter/application/sync/payloads/producto_proveedor_dependencia.dart';
import 'package:pos_flutter/application/sync/payloads/supplier_json.dart';

import '../../../support/supplier_contract_fixtures.dart';

Map variant(Map json) => (json['variants'] as List).first as Map;
Map price(Map json) => (variant(json)['suppliers'] as List).first as Map;

void main() {
  test('varios proveedores: roundtrip canónico, cero y dependencias', () {
    final json = supplierFixture('producto_creado');
    final payload = ProductoCreadoPayload.fromJson(json);
    expect(payload.toJson(), json);
    expect(payload.variantes.single.proveedores, hasLength(2));
    expect(payload.supplierIds, hasLength(2));
    expect(payload.variantes.single.proveedores!.first.quotedPriceMinor, 0);
    expect(payload.dependenciasProveedores.first.dependsOnEventId, isNotNull);
    final v = payload.variantes.single;
    expect(
      ProductoCreadoPayload.create(
        nombre: payload.nombre,
        categoriaId: null,
        saleConfiguration: payload.saleConfiguration,
        variantes: [
          ProductoCreadoVariante.create(
            id: v.id,
            nombre: v.nombre,
            precioVentaMenor: v.precioVentaMenor,
            costoEstandarMenor: v.costoEstandarMenor,
            orden: v.orden,
            proveedores: v.proveedores!.reversed.toList(),
          ),
        ],
        dependenciasProveedores: payload.dependenciasProveedores.reversed
            .toList(),
      ).toJson(),
      json,
    );
    expect(() => v.proveedores!.clear(), throwsUnsupportedError);
  });

  test(
    'producto medido conserva referencia y receta al añadir proveedores',
    () {
      final json = supplierFixture('producto_medido_con_receta');
      final payload = ProductoCreadoPayload.fromJson(json);
      expect(payload.toJson(), json);
      expect(
        payload.variantes.single.componentesReceta.single.quantityAtomic,
        1000,
      );
      expect(payload.variantes.single.proveedores, hasLength(2));
      final unknown = supplierFixture('producto_medido_con_receta');
      variant(unknown).remove('suppliers');
      (unknown['dependencies'] as List).removeWhere(
        (d) => (d as Map)['ref_type'] == 'supplier',
      );
      final legacy = ProductoCreadoPayload.fromJson(unknown);
      expect(payload.saleConfiguration, legacy.saleConfiguration);
      expect(
        payload.variantes.single.precioVentaMenor,
        legacy.variantes.single.precioVentaMenor,
      );
      expect(
        payload.variantes.single.costoEstandarMenor,
        legacy.variantes.single.costoEstandarMenor,
      );
    },
  );

  test('lista vacía es explícita y ausencia legada sobrevive roundtrip', () {
    final legacyJson = supplierFixture('producto_legado');
    final emptyJson = supplierFixture('producto_sin_proveedores');
    final legacy = ProductoCreadoPayload.fromJson(legacyJson);
    final empty = ProductoCreadoPayload.fromJson(emptyJson);
    expect(legacy.variantes.single.proveedores, isNull);
    expect(empty.variantes.single.proveedores, isEmpty);
    expect(legacy.toJson(), legacyJson);
    expect(empty.toJson(), emptyJson);
    expect(ProductoActualizadoPayload.sameState(legacy, empty), isFalse);
  });

  test(
    'retirada explícita conserva before y no altera venta/costo/inventario',
    () {
      final json = supplierFixture('producto_retirada_explicita');
      final payload = ProductoActualizadoPayload.fromJson(json);
      expect(payload.toJson(), json);
      expect(
        ProductoActualizadoPayload.sameState(payload.before, payload.after),
        isFalse,
      );
      final v = payload.after.variantes.single;
      expect(v.proveedores, isEmpty);
      expect(
        v.precioVentaMenor,
        payload.before.variantes.single.precioVentaMenor,
      );
      expect(
        v.costoEstandarMenor,
        payload.before.variantes.single.costoEstandarMenor,
      );
      expect(v.componentesReceta, isEmpty);
      expect(v.inventoryItemId, isNull);
      expect(payload.dependencyEventIds, {payload.baseEventId});
    },
  );

  test(
    'edición desconocida no puede omitir una lista conocida ni inventar base',
    () {
      final known = ProductoCreadoPayload.fromJson(
        supplierFixture('producto_creado'),
      );
      final legacy = ProductoCreadoPayload.fromJson(
        supplierFixture('producto_legado'),
      );
      for (final pair in [(known, legacy), (legacy, known)]) {
        expect(
          () => ProductoActualizadoPayload(
            baseEventId: 'base',
            before: pair.$1,
            after: pair.$2,
          ),
          throwsFormatException,
        );
      }
      final edit = ProductoActualizadoPayload(
        baseEventId: 'base',
        before: legacy,
        after: legacy,
      );
      expect(
        ProductoActualizadoPayload.fromJson(
          edit.toJson(),
        ).before.variantes.single.proveedores,
        isNull,
      );
      // La comprobación de before contra el estado actual impide borrar datos desconocidos.
      expect(ProductoActualizadoPayload.sameState(known, edit.before), isFalse);
    },
  );

  test(
    'sameState incluye precio, fecha y presencia; orden de proveedores irrelevante',
    () {
      final original = ProductoCreadoPayload.fromJson(
        supplierFixture('producto_creado'),
      );
      for (final field in ['quoted_price_minor', 'quoted_at_ms']) {
        final json = supplierFixture('producto_creado');
        price(json)[field] = (price(json)[field] as int) + 1;
        expect(
          ProductoActualizadoPayload.sameState(
            original,
            ProductoCreadoPayload.fromJson(json),
          ),
          isFalse,
        );
      }
      final reversed = supplierFixture('producto_creado');
      variant(reversed)['suppliers'] = (variant(reversed)['suppliers'] as List)
          .reversed
          .toList();
      expect(
        ProductoActualizadoPayload.sameState(
          original,
          ProductoCreadoPayload.fromJson(reversed),
        ),
        isTrue,
      );
      final edit = ProductoActualizadoPayload(
        baseEventId: 'base',
        before: original,
        after: original,
      );
      expect(
        edit.dependencyEventIds,
        contains(original.dependenciasProveedores.first.dependsOnEventId),
      );
    },
  );

  for (final field in ['supplier_id', 'quoted_price_minor', 'quoted_at_ms']) {
    final invalid = field == 'supplier_id'
        ? <Object?>[null, '', 'not-uuid', 1, true]
        : <Object?>[
            null,
            '',
            '0',
            -1,
            1.5,
            1.0,
            true,
            9007199254740992,
            if (field == 'quoted_at_ms') 0,
          ];
    for (final value in invalid) {
      test('rechaza $field=$value', () {
        final json = supplierFixture('producto_creado');
        price(json)[field] = value;
        expect(
          () => ProductoCreadoPayload.fromJson(json),
          throwsFormatException,
        );
      });
    }
    test('requiere $field', () {
      final json = supplierFixture('producto_creado');
      price(json).remove(field);
      expect(() => ProductoCreadoPayload.fromJson(json), throwsFormatException);
    });
  }
  for (final value in [
    null,
    {},
    '',
    0,
    [null],
  ]) {
    test('suppliers explícito inválido $value', () {
      final json = supplierFixture('producto_creado');
      variant(json)['suppliers'] = value;
      expect(() => ProductoCreadoPayload.fromJson(json), throwsFormatException);
    });
  }
  test('rango superior, UUID canónico y campos futuros', () {
    final json = supplierFixture('producto_creado');
    price(json)['quoted_price_minor'] = SupplierJson.maxSafeInteger;
    price(json)['quoted_at_ms'] = SupplierJson.maxSafeInteger;
    price(json)['future'] = true;
    final p = ProductoCreadoPayload.fromJson(
      json,
    ).variantes.single.proveedores!.first;
    expect(p.quotedPriceMinor, SupplierJson.maxSafeInteger);
    expect(p.toJson().containsKey('future'), isFalse);
    expect(
      ProductoProveedorPrecio(
        supplierId: 'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA',
        quotedPriceMinor: 0,
        quotedAtMs: 1,
      ).supplierId,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );
  });
  test('duplicados se rechazan aun con diferente precio o mayúsculas', () {
    final json = supplierFixture('producto_creado');
    final first = price(json);
    (variant(json)['suppliers'] as List).add({
      ...first,
      'quoted_price_minor': 42,
    });
    expect(() => ProductoCreadoPayload.fromJson(json), throwsFormatException);
    final p = ProductoProveedorPrecio(
      supplierId: 'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA',
      quotedPriceMinor: 0,
      quotedAtMs: 1,
    );
    expect(
      () => ProductoProveedorPrecio.validate([
        p,
        ProductoProveedorPrecio(
          supplierId: p.supplierId,
          quotedPriceMinor: 1,
          quotedAtMs: 1,
        ),
      ]),
      throwsFormatException,
    );
  });
  for (final change in [
    'missing',
    'extra',
    'duplicate',
    'invalid-id',
    'invalid-event',
  ]) {
    test('dependencias supplier $change', () {
      final json = supplierFixture('producto_creado');
      final deps = json['dependencies'] as List;
      switch (change) {
        case 'missing':
          deps.removeLast();
        case 'extra':
          deps.add({
            'ref_type': 'supplier',
            'ref_id': '00000000-0000-4000-8000-000000000099',
          });
        case 'duplicate':
          deps.add(deps.first);
        case 'invalid-id':
          (deps.first as Map)['ref_id'] = 'bad';
        case 'invalid-event':
          (deps.first as Map)['depends_on_event_id'] = '';
      }
      expect(() => ProductoCreadoPayload.fromJson(json), throwsFormatException);
    });
  }
  test(
    'constructor valida dependencias y proveedores sin depender del parser',
    () {
      expect(
        () => ProductoProveedorDependencia(refId: 'bad'),
        throwsFormatException,
      );
      expect(
        () => ProductoProveedorPrecio(
          supplierId: '00000000-0000-4000-8000-000000000002',
          quotedPriceMinor: -1,
          quotedAtMs: 1,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'dos variantes pueden compartir proveedor; no acepta snapshots parciales',
    () {
      final json = supplierFixture('producto_creado');
      final second = {
        ...variant(json),
        'variant_id': '00000000-0000-4000-8000-000000000099',
        'sort_order': 1,
      };
      (json['variants'] as List).add(second);
      expect(ProductoCreadoPayload.fromJson(json).variantes, hasLength(2));
      second.remove('suppliers');
      expect(() => ProductoCreadoPayload.fromJson(json), throwsFormatException);
    },
  );
}
