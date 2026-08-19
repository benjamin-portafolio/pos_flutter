import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/recurso_inventario_creado_payload.dart';

void main() {
  const itemId = '20000000-0000-4000-8000-000000000001';
  const unitId = '10000000-0000-4000-8000-000000000003';
  const movementId = '30000000-0000-4000-8000-000000000001';

  test('normaliza nombre y movimiento y conserva enteros atómicos', () {
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
    expect(
      payload.toJson()['initial_movement'],
      containsPair('quantity_delta_atomic', -250),
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
}
