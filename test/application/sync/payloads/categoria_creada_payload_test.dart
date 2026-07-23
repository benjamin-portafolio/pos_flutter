import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/categoria_creada_payload.dart';
import 'package:pos_flutter/domain/categorias/color_categoria.dart';

void main() {
  test('fromJson normaliza y tipa categoria_creada', () {
    final payload = CategoriaCreadaPayload.fromJson(const {
      'name': ' Bebidas ',
      'color_key': 'cyan',
      'sort_order': 2.0,
    });

    expect(payload.nombre, 'Bebidas');
    expect(payload.color, ColorCategoria.cyan);
    expect(payload.orden, 2);
    expect(payload.toJson(), {
      'name': 'Bebidas',
      'color_key': 'cyan',
      'sort_order': 2,
    });
  });

  test('fromJson rechaza campos invalidos de categoria_creada', () {
    expect(
      () => CategoriaCreadaPayload.fromJson(const {
        'name': ' ',
        'color_key': 'cyan',
        'sort_order': null,
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CategoriaCreadaPayload.fromJson(const {
        'name': 'Bebidas',
        'color_key': 'desconocido',
        'sort_order': null,
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CategoriaCreadaPayload.fromJson(const {
        'name': 'Bebidas',
        'color_key': 'cyan',
        'sort_order': 1.5,
      }),
      throwsA(isA<FormatException>()),
    );
  });
}
