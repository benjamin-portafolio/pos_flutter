import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/inventory_quantity_codec.dart';
import 'package:pos_flutter/domain/inventario/unidad_inventario.dart';

void main() {
  final fixtures =
      jsonDecode(
            File(
              'test/fixtures/minimum_stock_v1/contracts.json',
            ).readAsStringSync(),
          )
          as Map;
  Map<String, Object?> map(Object? value) =>
      Map<String, Object?>.from(value as Map);
  for (final fixture in fixtures['creations'] as List) {
    test('alta equivalente: ${fixture['name']}', () {
      final json = map(fixture['payload']);
      if (fixture['valid'] == false) {
        expect(
          () => ProductoCreadoPayload.fromJson(json),
          throwsFormatException,
        );
        return;
      }
      final parsed = ProductoCreadoPayload.fromJson(json);
      expect(parsed.toJson(), json);
      expect(ProductoCreadoPayload.fromJson(parsed.toJson()).toJson(), json);
      expect(
        ProductoCreadoPayload.knowsMinimumStockJson(json),
        parsed.knowsMinimumStock,
      );
      // Ambas operaciones de copia preservan el conocimiento y valores del otro campo.
      expect(
        parsed.withKnownSuppliers().knowsMinimumStock,
        parsed.knowsMinimumStock,
      );
      expect(
        parsed.withKnownSuppliers().variantes.map((v) => v.minimumStockAtomic),
        parsed.variantes.map((v) => v.minimumStockAtomic),
      );
      expect(
        parsed.withKnownMinimumStock().variantes.map((v) => v.proveedores),
        parsed.variantes.map((v) => v.proveedores),
      );
    });
  }
  for (final fixture in fixtures['updates'] as List) {
    test('edición equivalente: ${fixture['name']}', () {
      final json = map(fixture['payload']);
      if (fixture['valid'] == false) {
        expect(
          () => ProductoActualizadoPayload.fromJson(json),
          throwsFormatException,
        );
      } else {
        expect(ProductoActualizadoPayload.fromJson(json).toJson(), json);
      }
    });
  }
  for (final fixture in fixtures['comparisons'] as List) {
    test('base equivalente: ${fixture['name']}', () {
      final current = ProductoCreadoPayload.fromJson(map(fixture['current']));
      final before = ProductoCreadoPayload.fromJson(map(fixture['before']));
      expect(
        ProductoActualizadoPayload.sameState(current, before),
        fixture['same_state'],
      );
      expect(
        ProductoActualizadoPayload.sameEditingBase(current, before),
        fixture['same_base'],
      );
    });
  }
  test(
    'constructores anteriores no convierten null por defecto en retirada',
    () {
      final legacy = ProductoCreadoPayload.simple(
        nombre: 'Café',
        categoriaId: null,
        varianteId: '00000000-0000-4000-8000-000000000001',
        precioVentaMenor: 1000,
      );
      expect(legacy.knowsMinimumStock, isFalse);
      expect(
        legacy.variantes.single.toJson().containsKey('minimum_stock_atomic'),
        isFalse,
      );
      expect(
        legacy
            .withKnownMinimumStock()
            .variantes
            .single
            .toJson()['minimum_stock_atomic'],
        isNull,
      );
      expect(legacy.withKnownMinimumStock().knowsMinimumStock, isTrue);
      expect(
        ProductoActualizadoPayload.sameState(
          legacy,
          legacy.withKnownMinimumStock(),
        ),
        isTrue,
      );
      expect(
        ProductoActualizadoPayload.sameEditingBase(
          legacy.withKnownMinimumStock(),
          legacy,
        ),
        isFalse,
      );
    },
  );
  for (final value in [double.nan, double.infinity, double.negativeInfinity]) {
    test('rechaza número Dart no entero tipado $value', () {
      final json = map((fixtures['creations'] as List).first['payload']);
      final variant = map((json['variants'] as List).first);
      variant['minimum_stock_atomic'] = value;
      json['variants'] = [variant];
      expect(() => ProductoCreadoPayload.fromJson(json), throwsFormatException);
    });
  }
  test('codec existente: mínimo 1.5 kg son 1500 átomos y cero es válido', () {
    const codec = InventoryQuantityCodec();
    const kg = UnidadInventario(
      id: 'kg',
      code: 'kg',
      nombre: 'Kilogramo',
      simbolo: 'kg',
      dimension: DimensionUnidad.mass,
      factorAtomico: 1000,
      maximosDecimales: 3,
      activa: true,
    );
    const piece = UnidadInventario(
      id: 'piece',
      code: 'piece',
      nombre: 'Pieza',
      simbolo: 'pza',
      dimension: DimensionUnidad.count,
      factorAtomico: 1,
      maximosDecimales: 0,
      activa: true,
    );
    expect(codec.parseNonNegativeAtomic('1.5', kg), 1500);
    expect(codec.parseNonNegativeAtomic('0', piece), 0);
    for (final input in ['-1', '0.5', '9007199254740992']) {
      expect(
        () => codec.parseNonNegativeAtomic(input, piece),
        throwsFormatException,
      );
    }
    expect(
      () => codec.parseNonNegativeAtomic('1.0001', kg),
      throwsFormatException,
    );
  });
}
