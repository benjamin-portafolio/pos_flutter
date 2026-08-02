import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/categoria_movida_payload.dart';

void main() {
  test('serializa y decodifica un intercambio consecutivo', () {
    final payload = CategoriaMovidaPayload.fromValues(
      baseEventId: 'event_moved',
      ordenAnterior: 2,
      ordenNuevo: 1,
      categoriaDesplazadaId: 'category_2',
      categoriaDesplazadaBaseEventId: 'event_displaced',
      categoriaDesplazadaBaseVersion: 3,
      categoriaDesplazadaBaseServerSequence: 9,
      categoriaDesplazadaOrdenAnterior: 1,
      categoriaDesplazadaOrdenNuevo: 2,
    );

    final decoded = CategoriaMovidaPayload.fromJson(payload.toJson());

    expect(decoded.baseEventId, 'event_moved');
    expect(decoded.ordenAnterior, 2);
    expect(decoded.ordenNuevo, 1);
    expect(decoded.categoriaDesplazadaId, 'category_2');
    expect(decoded.categoriaDesplazadaBaseVersion, 3);
    expect(decoded.categoriaDesplazadaBaseServerSequence, 9);
  });

  test('rechaza posiciones no consecutivas o que no se intercambian', () {
    expect(
      () => CategoriaMovidaPayload.fromValues(
        baseEventId: 'event_moved',
        ordenAnterior: 3,
        ordenNuevo: 0,
        categoriaDesplazadaId: 'category_2',
        categoriaDesplazadaBaseEventId: 'event_displaced',
        categoriaDesplazadaBaseVersion: 1,
        categoriaDesplazadaBaseServerSequence: null,
        categoriaDesplazadaOrdenAnterior: 0,
        categoriaDesplazadaOrdenNuevo: 3,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rechaza changed_fields distintos de sort_order', () {
    expect(
      () => CategoriaMovidaPayload.fromJson(const {
        'base_event_id': 'event_moved',
        'changed_fields': ['name'],
        'changes': {
          'sort_order': {'from': 1, 'to': 0},
        },
        'displaced_category': {
          'category_id': 'category_1',
          'base_event_id': 'event_displaced',
          'base_version': 1,
          'base_server_sequence': null,
          'sort_order': {'from': 0, 'to': 1},
        },
      }),
      throwsA(isA<FormatException>()),
    );
  });
}
