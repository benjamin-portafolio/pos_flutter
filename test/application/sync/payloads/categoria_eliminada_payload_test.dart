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

  test('rechaza resoluciones futuras y productos vinculados', () {
    final futureResolution = _payload()
      ..['product_resolution'] = {'type': 'move'};
    expect(
      () => CategoriaEliminadaPayload.fromJson(futureResolution),
      throwsFormatException,
    );

    final linked = _payload()..['linked_products'] = ['product_1'];
    expect(
      () => CategoriaEliminadaPayload.fromJson(linked),
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
