import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/venta_borrador_limpiada_payload.dart';

void main() {
  test('normaliza referencias y conserva el contrato al serializar', () {
    final payload = VentaBorradorLimpiadaPayload(
      saleItemIds: ['  first  ', 'second'],
    );
    expect(payload.saleItemIds, ['first', 'second']);
    expect(
      VentaBorradorLimpiadaPayload.fromJson({
        ...payload.toJson(),
        'unknown': true,
      }).toJson(),
      payload.toJson(),
    );
    expect(VentaBorradorLimpiadaPayload(saleItemIds: []).toJson(), {
      'sale_item_ids': <String>[],
    });
  });

  test('rechaza referencias vacías, duplicadas o de tipo incorrecto', () {
    for (final json in <Map<String, Object?>>[
      {},
      {'sale_item_ids': 'line'},
      {
        'sale_item_ids': [null],
      },
      {
        'sale_item_ids': [' '],
      },
      {
        'sale_item_ids': ['line', ' line '],
      },
    ]) {
      expect(
        () => VentaBorradorLimpiadaPayload.fromJson(json),
        throwsFormatException,
      );
    }
  });
}
