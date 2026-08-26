import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';

void main() {
  test('normaliza y conserva la forma canónica del alta sencilla', () {
    final payload = ProductoCreadoPayload.simple(
      nombre: '  Café  ',
      categoriaId: null,
      varianteId: _variant1,
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
          'variant_id': _variant1,
          'name': null,
          'sku': null,
          'barcode': null,
          'sale_price_minor': 5050,
          'standard_cost_minor': null,
          'is_default': true,
          'sort_order': 0,
        },
      ],
      'dependencies': <Object?>[],
    });
  });

  test('normaliza varias variantes, nombres y costos', () {
    final payload = ProductoCreadoPayload.create(
      nombre: 'Café',
      categoriaId: null,
      saleConfiguration: const UnitSaleConfiguration(),
      variantes: [
        ProductoCreadoVariante.create(
          id: _variant1,
          nombre: '  Ｇｒａｎｄｅ  ',
          precioVentaMenor: 1000,
          costoEstandarMenor: 200,
          esPredeterminada: true,
          orden: 0,
        ),
        ProductoCreadoVariante.create(
          id: _variant2,
          nombre: '',
          precioVentaMenor: 1200,
          costoEstandarMenor: 0,
          esPredeterminada: false,
          orden: 1,
        ),
      ],
    );

    expect(payload.variantes.map((variant) => variant.nombre), [
      'Grande',
      null,
    ]);
    expect(payload.variantes.first.nameKey, 'grande');
    expect(payload.variantes.last.costoEstandarMenor, 0);
    expect(
      (payload.toJson()['variants']! as List)
          .cast<Map>()
          .last['standard_cost_minor'],
      0,
    );
  });

  test('un evento histórico sin costo se normaliza a null explícito', () {
    final json = ProductoCreadoPayload.simple(
      nombre: 'Café',
      categoriaId: null,
      varianteId: _variant1,
      precioVentaMenor: 5000,
    ).toJson();
    final variant = (json['variants']! as List).single as Map<String, Object?>;
    variant.remove('standard_cost_minor');

    final canonical = ProductoCreadoPayload.fromJson(json).toJson();
    expect(
      ((canonical['variants']! as List).single as Map)['standard_cost_minor'],
      isNull,
    );
  });

  test('rechaza duplicados normalizados, IDs, orden y predeterminada', () {
    final valid = _advancedJson();

    final duplicateName = _copyJson(valid);
    (duplicateName['variants']! as List)[1]['name'] = 'ＧＲＡＮＤＥ';
    expect(
      () => ProductoCreadoPayload.fromJson(duplicateName),
      throwsFormatException,
    );

    final duplicateId = _copyJson(valid);
    (duplicateId['variants']! as List)[1]['variant_id'] = _variant1;
    expect(
      () => ProductoCreadoPayload.fromJson(duplicateId),
      throwsFormatException,
    );

    final invalidOrder = _copyJson(valid);
    (invalidOrder['variants']! as List)[1]['sort_order'] = 2;
    expect(
      () => ProductoCreadoPayload.fromJson(invalidOrder),
      throwsFormatException,
    );

    final invalidDefault = _copyJson(valid);
    (invalidDefault['variants']! as List)[1]['is_default'] = true;
    expect(
      () => ProductoCreadoPayload.fromJson(invalidDefault),
      throwsFormatException,
    );
  });

  test('costo acepta null, cero y positivos y rechaza negativos', () {
    for (final cost in <int?>[null, 0, 1, 9007199254740991]) {
      final json = _advancedJson();
      (json['variants']! as List)[0]['standard_cost_minor'] = cost;
      expect(
        ProductoCreadoPayload.fromJson(json).variantes.first.costoEstandarMenor,
        cost,
      );
    }

    final negative = _advancedJson();
    (negative['variants']! as List)[0]['standard_cost_minor'] = -1;
    expect(
      () => ProductoCreadoPayload.fromJson(negative),
      throwsFormatException,
    );
  });

  test('serializa measured y su dependencia de unidad', () {
    final payload = ProductoCreadoPayload.simple(
      nombre: 'Queso',
      categoriaId: null,
      varianteId: _variant1,
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

  test('normaliza dependencias vigentes y legadas de categoría', () {
    final current = ProductoCreadoPayload.simple(
      nombre: 'Café',
      categoriaId: 'category_1',
      varianteId: _variant1,
      precioVentaMenor: 5000,
      dependenciaCategoria: const ProductoCreadoDependencia(
        refId: 'category_1',
        dependsOnEventId: 'category_created_1',
      ),
    );
    expect(current.toJson()['dependencies'], [
      {
        'ref_type': 'category',
        'ref_id': 'category_1',
        'depends_on_event_id': 'category_created_1',
      },
    ]);

    final legacy = ProductoCreadoPayload.simple(
      nombre: 'Café',
      categoriaId: 'category_1',
      varianteId: _variant1,
      precioVentaMenor: 5000,
    ).toJson();
    legacy['dependencies'] = [
      {
        'ref_type': 'category',
        'ref_id': 'category_1',
        'base_event_id': 'legacy_category_event',
        'base_version': 4,
        'base_server_sequence': 20,
      },
    ];
    expect(ProductoCreadoPayload.fromJson(legacy).toJson()['dependencies'], [
      {
        'ref_type': 'category',
        'ref_id': 'category_1',
        'depends_on_event_id': 'legacy_category_event',
      },
    ]);
  });
}

Map<String, Object?> _advancedJson() {
  return ProductoCreadoPayload.create(
    nombre: 'Café',
    categoriaId: null,
    saleConfiguration: const UnitSaleConfiguration(),
    variantes: [
      ProductoCreadoVariante.create(
        id: _variant1,
        nombre: 'Grande',
        precioVentaMenor: 1000,
        costoEstandarMenor: 200,
        esPredeterminada: true,
        orden: 0,
      ),
      ProductoCreadoVariante.create(
        id: _variant2,
        nombre: 'Chica',
        precioVentaMenor: 800,
        costoEstandarMenor: null,
        esPredeterminada: false,
        orden: 1,
      ),
    ],
  ).toJson();
}

Map<String, Object?> _copyJson(Map<String, Object?> source) {
  return {
    ...source,
    'product': {...source['product']! as Map},
    'variants': [
      for (final variant in source['variants']! as List) {...variant as Map},
    ],
    'dependencies': [
      for (final dependency in source['dependencies']! as List)
        {...dependency as Map},
    ],
  };
}

const _variant1 = '00000000-0000-4000-8000-000000000001';
const _variant2 = '00000000-0000-4000-8000-000000000002';
