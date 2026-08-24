import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';

void main() {
  test('normaliza y conserva la forma canónica del alta sencilla', () {
    final payload = ProductoCreadoPayload.simple(
      nombre: '  Café  ',
      categoriaId: null,
      varianteId: 'variant_1',
      precioVentaMenor: 5050,
    );

    expect(ProductoCreadoPayload.fromJson(payload.toJson()).toJson(), {
      'product': {
        'name': 'Café',
        'category_id': null,
        'sale_configuration': {'mode': 'unit'},
      },
      'variants': [
        {
          'variant_id': 'variant_1',
          'name': null,
          'sku': null,
          'barcode': null,
          'sale_price_minor': 5050,
          'is_default': true,
          'sort_order': 0,
        },
      ],
      'dependencies': <Object?>[],
    });
  });

  test('serializa measured y su dependencia de unidad', () {
    final payload = ProductoCreadoPayload.simple(
      nombre: 'Queso',
      categoriaId: null,
      varianteId: 'variant_1',
      precioVentaMenor: 18000,
      saleConfiguration: MeasuredSaleConfiguration(
        saleUnitId: 'unit_kg',
        priceReferenceQuantityAtomic: 1000,
      ),
    );

    expect(payload.toJson()['product'], {
      'name': 'Queso',
      'category_id': null,
      'sale_configuration': {
        'mode': 'measured',
        'sale_unit_id': 'unit_kg',
        'price_reference_quantity_atomic': 1000,
      },
    });
    expect(payload.toJson()['dependencies'], [
      {'ref_type': 'unit', 'ref_id': 'unit_kg'},
    ]);
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

  test('una categoría oficial no requiere dependencia de evento', () {
    final payload = ProductoCreadoPayload.simple(
      nombre: 'Café',
      categoriaId: 'category_1',
      varianteId: 'variant_1',
      precioVentaMenor: 5000,
    );

    expect(payload.toJson()['dependencies'], isEmpty);
    expect(
      ProductoCreadoPayload.fromJson(payload.toJson()).categoriaId,
      'category_1',
    );
  });

  test('serializa la dependencia local con depends_on_event_id', () {
    final payload = ProductoCreadoPayload.simple(
      nombre: 'Café',
      categoriaId: 'category_1',
      varianteId: 'variant_1',
      precioVentaMenor: 5000,
      dependenciaCategoria: const ProductoCreadoDependencia(
        refId: 'category_1',
        dependsOnEventId: 'category_created_1',
      ),
    );

    expect(payload.toJson()['dependencies'], [
      {
        'ref_type': 'category',
        'ref_id': 'category_1',
        'depends_on_event_id': 'category_created_1',
      },
    ]);
  });

  test('lee una dependencia legada y la normaliza al contrato nuevo', () {
    final json = ProductoCreadoPayload.simple(
      nombre: 'Café',
      categoriaId: 'category_1',
      varianteId: 'variant_1',
      precioVentaMenor: 5000,
    ).toJson();
    json['dependencies'] = [
      {
        'ref_type': 'category',
        'ref_id': 'category_1',
        'base_event_id': 'legacy_category_event',
        'base_version': 4,
        'base_server_sequence': 20,
      },
    ];

    expect(ProductoCreadoPayload.fromJson(json).toJson()['dependencies'], [
      {
        'ref_type': 'category',
        'ref_id': 'category_1',
        'depends_on_event_id': 'legacy_category_event',
      },
    ]);
  });
}
