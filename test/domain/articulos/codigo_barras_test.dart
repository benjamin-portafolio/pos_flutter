import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/articulos/codigo_barras.dart';

void main() {
  test('convierte vacío y espacios en ausencia de código', () {
    expect(CodigoBarras.fromInput(null).value, isNull);
    expect(CodigoBarras.fromInput('').value, isNull);
    expect(CodigoBarras.fromInput('   ').value, isNull);
  });

  test('normaliza con NFKC y recorta', () {
    expect(CodigoBarras.fromInput('  012345678905  ').value, '012345678905');
    // Dígitos de ancho completo: NFKC los reduce a ASCII.
    expect(CodigoBarras.fromInput('０１２３４５６７８９０５').value, '012345678905');
  });

  test('conserva los ceros a la izquierda como texto', () {
    const upcA = '012345678905';

    final codigo = CodigoBarras.fromInput(upcA);

    expect(codigo.value, upcA);
    // No es un número: eliminar los ceros iniciales sería una pérdida real.
    expect(codigo.value, isNot(equals(int.parse(upcA).toString())));
    expect(codigo.value!.length, 12);
  });

  test('admite GS1-128 con identificadores de aplicación', () {
    expect(CodigoBarras.fromInput('01034567890128').value, '01034567890128');
  });

  test('acepta longitudes de 1 y de 32 dígitos', () {
    expect(CodigoBarras.fromInput('7').value, '7');
    expect(CodigoBarras.fromInput('1' * 32).value, '1' * 32);
  });

  test('rechaza valores que no son solo dígitos', () {
    for (final invalid in <String>[
      'ABC123',
      '12-345',
      '12.5',
      '12_45',
      '12 45',
      '7501234567890X',
      '١٢٣',
      '1' * 33,
      '+123',
    ]) {
      expect(
        () => CodigoBarras.fromInput(invalid),
        throwsArgumentError,
        reason: 'debe rechazar "$invalid"',
      );
    }
  });

  // La UI depende de este contrato: la captura manual entrega texto crudo y
  // el valor normalizado es lo que se persiste.
  final accepted = <(String?, String?)>[
    (null, null),
    ('', null),
    ('   ', null),
    ('750802876102', '750802876102'),
    ('012345678905', '012345678905'),
    ('  750802876102  ', '750802876102'),
    ('１２３', '123'),
    ('7', '7'),
    ('1' * 32, '1' * 32),
  ];
  final rejected = <(String, String)>[
    ('ABC123', 'letras'),
    ('750802876102A', 'letras al final'),
    ('1' * 33, 'más de 32 dígitos'),
    ('750 802 876 102', 'espacios internos'),
    ('12-345', 'guion'),
    ('١٢٣', 'dígitos no ASCII sin normalizar'),
    ('👩‍💻', 'emoji'),
  ];

  test('tabla de vectores aceptados', () {
    for (final (input, expected) in accepted) {
      expect(
        CodigoBarras.fromInput(input).value,
        expected,
        reason: 'entrada "$input"',
      );
    }
  });

  test('tabla de vectores rechazados', () {
    for (final (input, motivo) in rejected) {
      expect(
        () => CodigoBarras.fromInput(input),
        throwsArgumentError,
        reason: '$motivo: "$input"',
      );
    }
  });
}
