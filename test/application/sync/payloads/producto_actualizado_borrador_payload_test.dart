import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_borrador_payload.dart';
import 'package:pos_flutter/application/sync/payloads/sale_item_snapshot.dart';

void main() {
  final item = SaleItemSnapshot(
    variantId: 'coffee',
    productName: '  Café  ',
    saleMode: 'unit',
    quantity: 3,
    measuredQuantityAtomic: null,
    unitPriceMinor: 3500,
    standardCostMinor: 1000,
    priceReferenceQuantityAtomic: null,
    unitCode: null,
    unitSymbol: null,
    unitAtomicFactor: null,
  );

  test('conserva el contrato al serializar y permite campos desconocidos', () {
    final payload = ProductoActualizadoBorradorPayload(
      saleItemId: '  line-1  ',
      item: item,
    );
    expect(payload.saleItemId, 'line-1');
    expect(payload.item.quantity, 3);
    expect(
      ProductoActualizadoBorradorPayload.fromJson({
        ...payload.toJson(),
        'unknown': true,
      }).toJson(),
      payload.toJson(),
    );
  });

  test('rechaza identificadores y contenido de línea inválidos', () {
    final valid = ProductoActualizadoBorradorPayload(
      saleItemId: 'line-1',
      item: item,
    ).toJson();
    for (final json in <Map<String, Object?>>[
      {},
      {'sale_item_id': 'line-1'},
      {...valid, 'sale_item_id': ' '},
      {...valid, 'sale_item_id': 7},
      {...valid, 'variant_id': null},
    ]) {
      expect(
        () => ProductoActualizadoBorradorPayload.fromJson(json),
        throwsFormatException,
      );
    }
  });
}