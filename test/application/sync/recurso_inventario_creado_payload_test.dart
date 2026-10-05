import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/inventory_movement_payload.dart';
import 'package:pos_flutter/application/sync/payloads/recurso_inventario_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/recurso_inventario_creado_payload.dart';
import 'package:pos_flutter/domain/inventario/tipo_movimiento_inventario.dart';

import '../../fixtures/variant_tracking_fixture_loader.dart';

void main() {
  const itemId = '20000000-0000-4000-8000-000000000001';
  const unitId = '10000000-0000-4000-8000-000000000003';
  const movementId = '30000000-0000-4000-8000-000000000001';

  test('interpreta manual_adjustment histórico sin reescribirlo', () {
    final payload = RecursoInventarioCreadoPayload.fromJson(const {
      'inventory_item': {
        'inventory_item_id': itemId,
        'name': '  Ｈarina  ',
        'default_unit_id': unitId,
      },
      'initial_movement': {
        'movement_id': movementId,
        'movement_type': 'manual_adjustment',
        'quantity_delta_atomic': -250,
        'reason': '  Existencia inicial  ',
      },
    });

    expect(payload.name, 'Harina');
    expect(payload.initialMovement?.quantityDeltaAtomic, -250);
    expect(payload.initialMovement?.reason, 'Existencia inicial');
    expect(payload.initialMovement?.movementType.code, 'manual_adjustment');
    expect(
      payload.toJson()['initial_movement'],
      containsPair('quantity_delta_atomic', -250),
    );
  });

  test('acepta initial_balance positivo sin motivo para eventos nuevos', () {
    final payload = RecursoInventarioCreadoPayload.fromJson(const {
      'inventory_item': {
        'inventory_item_id': itemId,
        'name': 'Harina',
        'default_unit_id': unitId,
      },
      'initial_movement': {
        'movement_id': movementId,
        'movement_type': 'initial_balance',
        'quantity_delta_atomic': 250,
        'reason': null,
        'reversal_of_movement_id': null,
        'total_cost_minor': null,
      },
    });

    expect(payload.initialMovement?.movementType.code, 'initial_balance');
    expect(payload.initialMovement?.reason, isNull);
    expect(
      (payload.toJson()['initial_movement'] as Map)['movement_type'],
      'initial_balance',
    );
  });

  test('acepta null y rechaza cero, fracciones y motivo vacío', () {
    final withoutMovement = RecursoInventarioCreadoPayload.fromJson(const {
      'inventory_item': {
        'inventory_item_id': itemId,
        'name': 'Harina',
        'default_unit_id': unitId,
      },
      'initial_movement': null,
    });
    expect(withoutMovement.initialMovement, isNull);

    Map<String, Object?> invalidMovement(Object delta, String reason) => {
      'inventory_item': {
        'inventory_item_id': itemId,
        'name': 'Harina',
        'default_unit_id': unitId,
      },
      'initial_movement': {
        'movement_id': movementId,
        'movement_type': 'manual_adjustment',
        'quantity_delta_atomic': delta,
        'reason': reason,
      },
    };

    expect(
      () => RecursoInventarioCreadoPayload.fromJson(invalidMovement(0, 'x')),
      throwsFormatException,
    );
    expect(
      () => RecursoInventarioCreadoPayload.fromJson(invalidMovement(1.5, 'x')),
      throwsFormatException,
    );
    expect(
      () => RecursoInventarioCreadoPayload.fromJson(invalidMovement(1, ' ')),
      throwsFormatException,
    );
  });

  test('stock_receipt exige delta positivo y normaliza motivo opcional', () {
    final receipt = InventoryMovementPayload.create(
      movementId: movementId,
      movementType: TipoMovimientoInventario.stockReceipt,
      quantityDeltaAtomic: 10,
      reason: '  Ｃompra  ',
    );
    expect(receipt.reason, 'Compra');

    for (final delta in [0, -1]) {
      expect(
        () => InventoryMovementPayload.create(
          movementId: movementId,
          movementType: TipoMovimientoInventario.stockReceipt,
          quantityDeltaAtomic: delta,
        ),
        throwsFormatException,
      );
    }
  });

  test('manual_adjustment exige motivo y admite ambos signos', () {
    expect(
      () => InventoryMovementPayload.create(
        movementId: movementId,
        movementType: TipoMovimientoInventario.manualAdjustment,
        quantityDeltaAtomic: -1,
      ),
      throwsFormatException,
    );
    expect(
      InventoryMovementPayload.create(
        movementId: movementId,
        movementType: TipoMovimientoInventario.manualAdjustment,
        quantityDeltaAtomic: -1,
        reason: 'Conteo físico',
      ).quantityDeltaAtomic,
      -1,
    );
  });

  test('la actualización rechaza cualquier intento de cambiar unidad', () {
    expect(
      () => RecursoInventarioActualizadoPayload.fromJson(const {
        'base_event_id': 'event-base',
        'changed_fields': ['name'],
        'changes': {
          'name': {'from': 'Harina', 'to': 'Harina integral'},
        },
        'default_unit_id': unitId,
      }),
      throwsFormatException,
    );
  });

  // Procedencia (contrato rev. 1 §6.1). Los fixtures son los mismos que lee
  // NestJS, así que una revisión del contrato no puede quedar válida en un
  // lado y rota en el otro.
  group('origin_variant_id', () {
    test('lee y reemite la procedencia del recurso autogenerado', () {
      final parsed = RecursoInventarioCreadoPayload.fromJson(
        fixturePayload('alta/alta-autogenerada-origen-valido.json'),
      );

      expect(parsed.originVariantId, 'a2000000-0000-4000-8000-000000000001');
      final item = parsed.toJson()['inventory_item']! as Map<String, Object?>;
      expect(
        item[RecursoInventarioCreadoPayload.originVariantIdField],
        'a2000000-0000-4000-8000-000000000001',
      );
      // El resto de la forma canónica no cambia por añadir procedencia.
      expect(parsed.toJson()['initial_movement'], isNull);
      expect(item.keys.toSet(), {
        'inventory_item_id',
        'name',
        'default_unit_id',
        RecursoInventarioCreadoPayload.originVariantIdField,
      });
    });

    test('omite la clave en recursos independientes', () {
      final parsed = RecursoInventarioCreadoPayload.fromJson(
        fixturePayload('alta/alta-independiente.json'),
      );

      expect(parsed.originVariantId, isNull);
      final item = parsed.toJson()['inventory_item']! as Map<String, Object?>;
      expect(
        item.containsKey(RecursoInventarioCreadoPayload.originVariantIdField),
        isFalse,
      );
    });

    test('lee como desconocido el alta legada sin procedencia', () {
      final parsed = RecursoInventarioCreadoPayload.fromJson(
        fixturePayload('alta/alta-legada-sin-origen.json'),
      );

      // La ausencia de origen no invalida el resto del evento, ni el
      // `manual_adjustment` legado.
      expect(parsed.originVariantId, isNull);
      final movement = parsed.toJson()['initial_movement']! as Map;
      expect(movement['quantity_delta_atomic'], 500);
    });

    test('acepta el sobre del alta autogenerada con la misma procedencia', () {
      final parsed = RecursoInventarioCreadoPayload.fromJson(
        fixturePayload('alta/sobre-alta-valido.json'),
      );

      expect(parsed.originVariantId, 'a2000000-0000-4000-8000-000000000001');
    });

    test('create valida el origen y no lo exige', () {
      expect(
        RecursoInventarioCreadoPayload.create(
          inventoryItemId: 'a3000000-0000-4000-8000-000000000001',
          name: 'Café molido 250 g',
          defaultUnitId: 'a5000000-0000-4000-8000-000000000002',
          originVariantId: 'a2000000-0000-4000-8000-000000000001',
        ).originVariantId,
        'a2000000-0000-4000-8000-000000000001',
      );
      expect(
        RecursoInventarioCreadoPayload.create(
          inventoryItemId: 'a3000000-0000-4000-8000-000000000002',
          name: 'Vela aromática',
          defaultUnitId: 'a5000000-0000-4000-8000-000000000001',
        ).originVariantId,
        isNull,
      );
      expect(
        () => RecursoInventarioCreadoPayload.create(
          inventoryItemId: 'a3000000-0000-4000-8000-000000000001',
          name: 'Café molido 250 g',
          defaultUnitId: 'a5000000-0000-4000-8000-000000000002',
          originVariantId: 'variante-250g',
        ),
        throwsFormatException,
      );
    });

    test('rechaza procedencia que no es texto ni UUID v4', () {
      for (final fixture in [
        'alta/alta-autogenerada-origen-no-string.json',
        'alta/alta-autogenerada-origen-no-uuid.json',
      ]) {
        expect(
          () =>
              RecursoInventarioCreadoPayload.fromJson(fixturePayload(fixture)),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('UUID v4'),
            ),
          ),
          reason: fixture,
        );
      }
    });

    test('no degrada a desconocido el alta legada con UUID no v4', () {
      // La procedencia ausente es `null`; la presente pero inválida se rechaza.
      // Convertirla en `null` fabricaría un recurso independiente.
      expect(
        () => RecursoInventarioCreadoPayload.fromJson(
          fixturePayload('alta/alta-legada-uuid-incorrecto.json'),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('UUID v4'),
          ),
        ),
      );
    });

    test('solo el alta establece procedencia', () {
      // Editar el nombre no la modifica: es una identidad del recurso, no un
      // campo editable del producto.
      expect(
        () => RecursoInventarioActualizadoPayload.fromJson(
          fixturePayload('escenarios/actualizacion-intenta-mutar-origen.json'),
        ),
        throwsFormatException,
      );
    });
  });
}

Map<String, Object?> fixturePayload(String relativePath) =>
    readVariantTrackingFixture(relativePath)['payload']!
        as Map<String, Object?>;
