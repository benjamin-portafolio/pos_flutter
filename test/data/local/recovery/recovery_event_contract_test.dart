import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/recovery/recovery_event_contract.dart';
import 'package:pos_flutter/application/sync/payloads/recurso_inventario_creado_payload.dart';

void main() {
  Map<String, Object?> payload() => {
    'inventory_item': {
      'inventory_item_id': '10000000-0000-4000-8000-000000000001',
      'name': 'Recurso legado',
      'default_unit_id': '10000000-0000-4000-8000-000000000002',
      'origin_variant_id': null,
    },
  };
  test(
    'legacy absence of initial movement and explicit unknown origin are admitted intact',
    () {
      final original = payload();
      expect(
        RecoveryEventContract.dependencies(
          RecursoInventarioCreadoPayload.eventType,
          original,
        ),
        isEmpty,
      );
      expect(
        (original['inventory_item'] as Map).containsKey('origin_variant_id'),
        isTrue,
      );
      expect(original.containsKey('initial_movement'), isFalse);
    },
  );
  test('unknown null payload fields are still rejected', () {
    for (final key in ['token', 'cash']) {
      final original = payload()..[key] = null;
      expect(
        () => RecoveryEventContract.dependencies(
          RecursoInventarioCreadoPayload.eventType,
          original,
        ),
        throwsFormatException,
      );
    }
  });
}
