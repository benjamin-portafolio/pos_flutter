import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/categoria_eliminada_payload.dart';

void main() {
  test('fromJson y toJson conservan el contrato canónico', () {
    final json = _payload();
    final payload = CategoriaEliminadaPayload.fromJson(json);

    expect(payload.baseEventId, 'event_base');
    expect(payload.categoriaEliminada.nombre, 'Test');
    expect(payload.categoriasDesplazadas.single.categoriaId, 'category_2');
    expect(payload.toJson(), json);
  });

  test('ignora campos adicionales', () {
    final json = _payload()..['future_field'] = true;
    expect(
      CategoriaEliminadaPayload.fromJson(json).toJson(),
      isNot(contains('future_field')),
    );
  });

  test('parsea move y conserva destino y productos canónicos', () {
    final json = _payload()
      ..['product_resolution'] = {
        'type': 'move',
        'destination_category': {
          'category_id': 'category_destination',
          'base_event_id': 'destination_base',
          'base_version': 4,
          'base_server_sequence': 30,
        },
      }
      ..['linked_products'] = [
        _linkedProduct('product_1', to: 'category_destination'),
        _linkedProduct('product_2', to: 'category_destination'),
      ];
    final parsed = CategoriaEliminadaPayload.fromJson(json);

    expect(parsed.resolucionProductos.tipo.name, 'move');
    expect(
      parsed.resolucionProductos.categoriaDestino!.categoriaId,
      'category_destination',
    );
    expect(parsed.productosVinculados, hasLength(2));
    expect(parsed.toJson(), json);
    expect(
      () => parsed.validateForSourceCategory('category_source'),
      returnsNormally,
    );
  });

  test(
    'parsea uncategorize con productos activos o inactivos indistintamente',
    () {
      final json = _payload()
        ..['product_resolution'] = {'type': 'uncategorize'}
        ..['linked_products'] = [
          _linkedProduct('product_1'),
          _linkedProduct('product_2'),
        ];
      final parsed = CategoriaEliminadaPayload.fromJson(json);

      expect(parsed.resolucionProductos.tipo.name, 'uncategorize');
      expect(
        parsed.productosVinculados.map((product) => product.categoriaNuevaId),
        everyElement(isNull),
      );
    },
  );

  test('rechaza delete y productos inválidos o no canónicos', () {
    final deletion = _payload()..['product_resolution'] = {'type': 'delete'};
    expect(
      () => CategoriaEliminadaPayload.fromJson(deletion),
      throwsFormatException,
    );

    final linked = _payload()..['linked_products'] = ['product_1'];
    expect(
      () => CategoriaEliminadaPayload.fromJson(linked),
      throwsFormatException,
    );

    final duplicated = _payload()
      ..['product_resolution'] = {'type': 'uncategorize'}
      ..['linked_products'] = [
        _linkedProduct('product_1'),
        _linkedProduct('product_1'),
      ];
    expect(
      () => CategoriaEliminadaPayload.fromJson(duplicated),
      throwsFormatException,
    );

    final invalidBase = _payload()
      ..['product_resolution'] = {'type': 'uncategorize'}
      ..['linked_products'] = [
        {..._linkedProduct('product_1'), 'base_version': 0},
      ];
    expect(
      () => CategoriaEliminadaPayload.fromJson(invalidBase),
      throwsFormatException,
    );
  });

  test('valida presencia, ausencia e identidad del destino', () {
    final withoutDestination = _payload()
      ..['product_resolution'] = {'type': 'move'};
    expect(
      () => CategoriaEliminadaPayload.fromJson(withoutDestination),
      throwsFormatException,
    );

    final unexpectedDestination = _payload()
      ..['product_resolution'] = {
        'type': 'uncategorize',
        'destination_category': null,
      };
    expect(
      () => CategoriaEliminadaPayload.fromJson(unexpectedDestination),
      throwsFormatException,
    );

    final sameDestination = _payload()
      ..['product_resolution'] = {
        'type': 'move',
        'destination_category': {
          'category_id': 'category_source',
          'base_event_id': 'destination_base',
          'base_version': 1,
          'base_server_sequence': null,
        },
      };
    final parsed = CategoriaEliminadaPayload.fromJson(sameDestination);
    expect(
      () => parsed.validateForSourceCategory('category_source'),
      throwsFormatException,
    );
  });

  test('rechaza huecos y desplazamientos que no sean from - 1', () {
    final json = _payload();
    final shifted = (json['shifted_categories']! as List).single as Map;
    shifted['sort_order'] = {'from': 3, 'to': 1};
    expect(
      () => CategoriaEliminadaPayload.fromJson(json),
      throwsFormatException,
    );
  });
}

Map<String, Object?> _payload() => {
  'base_event_id': 'event_base',
  'deleted_category': {
    'name': 'Test',
    'color_key': 'amber',
    'sort_order': 0,
    'active': true,
    'created_event_id': 'event_created',
  },
  'product_resolution': {'type': 'none'},
  'linked_products': <Object?>[],
  'shifted_categories': [
    {
      'category_id': 'category_2',
      'base_event_id': 'event_category_2',
      'base_version': 3,
      'base_server_sequence': 21,
      'sort_order': {'from': 1, 'to': 0},
    },
  ],
};

Map<String, Object?> _linkedProduct(String id, {String? to}) => {
  'product_id': id,
  'base_event_id': '${id}_base',
  'base_version': 2,
  'base_server_sequence': 25,
  'category_id': {'from': 'category_source', 'to': to},
};
