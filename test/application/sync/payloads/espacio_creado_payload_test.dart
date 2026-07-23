import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/espacio_creado_payload.dart';
import 'package:pos_flutter/domain/espacios/visibilidad_espacio.dart';

void main() {
  test('fromJson normaliza y tipa espacio_creado', () {
    final payload = EspacioCreadoPayload.fromJson(const {
      'nombre': ' Salon ',
      'identificacion': ' salon ',
      'visibilidad': 1,
    });

    expect(payload.nombre, 'Salon');
    expect(payload.identificacion, 'salon');
    expect(payload.visibilidad, VisibilidadEspacio.soloRestringido);
    expect(payload.toJson(), {
      'nombre': 'Salon',
      'identificacion': 'salon',
      'visibilidad': 'solo_restringido',
    });
  });

  test('fromJson convierte identificacion vacia a null', () {
    final payload = EspacioCreadoPayload.fromJson(const {
      'nombre': 'Salon',
      'identificacion': '  ',
      'visibilidad': 'sin_restriccion',
    });

    expect(payload.identificacion, isNull);
  });

  test('fromJson rechaza campos invalidos de espacio_creado', () {
    expect(
      () => EspacioCreadoPayload.fromJson(const {
        'nombre': ' ',
        'identificacion': null,
        'visibilidad': 'sin_restriccion',
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => EspacioCreadoPayload.fromJson(const {
        'nombre': 'Salon',
        'identificacion': 42,
        'visibilidad': 'sin_restriccion',
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => EspacioCreadoPayload.fromJson(const {
        'nombre': 'Salon',
        'identificacion': null,
        'visibilidad': 'desconocida',
      }),
      throwsA(isA<FormatException>()),
    );
  });
}
