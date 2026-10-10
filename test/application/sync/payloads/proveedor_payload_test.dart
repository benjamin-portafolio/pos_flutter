import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/proveedor_creado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/proveedor_actualizado_payload.dart';

import '../../../support/supplier_contract_fixtures.dart';

void main() {
  test(
    'fixtures de alta/edición tienen JSON canónico y base para reversión',
    () {
      final created = supplierFixture('proveedor_creado');
      final updated = supplierFixture('proveedor_actualizado');
      expect(ProveedorCreadoPayload.fromJson(created).toJson(), created);
      final payload = ProveedorActualizadoPayload.fromJson(updated);
      expect(payload.toJson(), updated);
      expect(payload.before.toJson(), created);
      expect(
        ProveedorActualizadoPayload.sameState(payload.before, payload.after),
        isFalse,
      );
      expect(ProveedorCreadoPayload.aggregateType, 'supplier');
      expect(ProveedorActualizadoPayload.aggregateType, 'supplier');
      expect(ProveedorCreadoPayload.eventType, 'proveedor_creado');
      expect(ProveedorActualizadoPayload.eventType, 'proveedor_actualizado');
    },
  );

  test('normaliza textos, conserva teléfono como texto e ignora extras', () {
    final payload = ProveedorCreadoPayload.fromJson({
      'name': '  Norte  ',
      'phone': '  00123  ',
      'notes': '  ',
      'future': 1,
    });
    expect(payload.toJson(), {
      'name': 'Norte',
      'phone': '00123',
      'notes': null,
    });
    expect(ProveedorCreadoPayload(name: 'Norte', phone: '').phone, isNull);
    expect(ProveedorCreadoPayload.fromJson({'name': 'Norte'}).toJson(), {
      'name': 'Norte',
      'phone': null,
      'notes': null,
    });
  });

  for (final field in ['name', 'phone', 'notes']) {
    for (final value in [1, true, [], {}]) {
      test('rechaza $field=$value', () {
        final json = supplierFixture('proveedor_creado')..[field] = value;
        expect(
          () => ProveedorCreadoPayload.fromJson(json),
          throwsFormatException,
        );
      });
    }
  }
  for (final value in [null, '', '  ', '\n\t']) {
    test('nombre obligatorio $value', () {
      expect(
        () => ProveedorCreadoPayload.fromJson({'name': value}),
        throwsFormatException,
      );
    });
  }
  test('constructor no evade nombre requerido', () {
    expect(() => ProveedorCreadoPayload(name: ' '), throwsFormatException);
  });
  for (final field in ['base_event_id', 'before', 'after']) {
    test('edición requiere $field', () {
      final json = supplierFixture('proveedor_actualizado')..remove(field);
      expect(
        () => ProveedorActualizadoPayload.fromJson(json),
        throwsFormatException,
      );
    });
  }
  test('base de proveedor exige UUID', () {
    final json = supplierFixture('proveedor_actualizado')
      ..['base_event_id'] = 'unknown';
    expect(
      () => ProveedorActualizadoPayload.fromJson(json),
      throwsFormatException,
    );
  });
}
