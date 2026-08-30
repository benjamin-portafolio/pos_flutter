import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/inventory_movement_payload.dart';
import 'package:pos_flutter/application/sync/payloads/recurso_inventario_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/recurso_inventario_creado_payload.dart';
import 'package:pos_flutter/domain/inventario/tipo_movimiento_inventario.dart';

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
}
