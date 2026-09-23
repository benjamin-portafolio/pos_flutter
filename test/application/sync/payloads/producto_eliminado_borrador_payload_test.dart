import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/producto_eliminado_borrador_payload.dart';

void main() {
  test('normaliza el identificador y conserva el contrato al serializar', () {
    final payload = ProductoEliminadoBorradorPayload(
      saleItemId: '  line-9  ',
    );
    expect(payload.saleItemId, 'line-9');
    expect(
      ProductoEliminadoBorradorPayload.fromJson({
        ...payload.toJson(),
        'unknown': true,
      }).toJson(),
      payload.toJson(),
    );
  });

  test('rechaza identificadores vacíos o de tipo incorrecto', () {
    for (final json in <Map<String, Object?>>[
      {},
      {'sale_item_id': 7},
      {'sale_item_id': null},
      {'sale_item_id': ' '},
      {'sale_item_id': ''},
    ]) {
      expect(
        () => ProductoEliminadoBorradorPayload.fromJson(json),
        throwsFormatException,
      );
    }
  });
}