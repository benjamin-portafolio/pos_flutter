import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/categoria_actualizada_payload.dart';
import 'package:pos_flutter/domain/categorias/color_categoria.dart';

void main() {
  test('fromValues conserva solo los campos que cambiaron', () {
    final payload = CategoriaActualizadaPayload.fromValues(
      baseEventId: 'event_previous',
      nombreAnterior: 'Bebidas',
      nombreNuevo: ' Bebidas ',
      colorAnterior: ColorCategoria.cyan,
      colorNuevo: ColorCategoria.blue,
    );

    expect(payload.changedFields, ['color_key']);
    expect(payload.toJson(), {
      'base_event_id': 'event_previous',
      'changed_fields': ['color_key'],
      'changes': {
        'color_key': {'from': 'cyan', 'to': 'blue'},
      },
    });
  });

  test('fromJson normaliza y tipa los cambios declarados', () {
    final payload = CategoriaActualizadaPayload.fromJson({
      'base_event_id': 'event_previous',
      'changed_fields': ['name', 'color_key'],
      'changes': {
        'name': {'from': ' Bebidas ', 'to': ' Bebidas frías '},
        'color_key': {'from': 'cyan', 'to': 'blue'},
      },
      'future_field': true,
    });

    expect(payload.nombreAnterior, 'Bebidas');
    expect(payload.nombreNuevo, 'Bebidas frías');
    expect(payload.colorAnterior, ColorCategoria.cyan);
    expect(payload.colorNuevo, ColorCategoria.blue);
  });

  test('fromJson rechaza campos desconocidos y cambios vacíos', () {
    expect(
      () => CategoriaActualizadaPayload.fromJson({
        'base_event_id': 'event_previous',
        'changed_fields': ['sort_order'],
        'changes': {
          'sort_order': {'from': null, 'to': 2},
        },
      }),
      throwsFormatException,
    );

    expect(
      () => CategoriaActualizadaPayload.fromJson({
        'base_event_id': 'event_previous',
        'changed_fields': ['name'],
        'changes': {
          'name': {'from': 'Bebidas', 'to': ' Bebidas '},
        },
      }),
      throwsFormatException,
    );
  });
}
