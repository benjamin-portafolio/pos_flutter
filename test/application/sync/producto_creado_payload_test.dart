import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';

void main() {
  test('normaliza y conserva la forma canónica del alta sencilla', () {
    final payload = ProductoCreadoPayload.simple(
      nombre: '  Café  ',
      categoriaId: null,
      varianteId: 'variant_1',
      precioVentaMenor: 5050,
    );

    expect(ProductoCreadoPayload.fromJson(payload.toJson()).toJson(), {
      'product': {'name': 'Café', 'category_id': null},
      'variants': [
        {
          'variant_id': 'variant_1',
          'name': null,
          'sku': null,
          'barcode': null,
          'sale_price_minor': 5050,
          'is_default': true,
          'sort_order': 0,
          'inventory_configuration': {'behavior': 'none'},
        },
      ],
      'dependencies': <Object?>[],
    });
  });

  test('rechaza variantes avanzadas en el alcance sencillo', () {
    final json = ProductoCreadoPayload.simple(
      nombre: 'Café',
      categoriaId: null,
      varianteId: 'variant_1',
      precioVentaMenor: 5000,
    ).toJson();
    final variant = (json['variants']! as List).single as Map<String, Object?>;
    variant['sku'] = 'CAFE-1';

    expect(
      () => ProductoCreadoPayload.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });
}
