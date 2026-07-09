import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/espacios/nombre_espacio.dart';

void main() {
  test('normaliza un nombre con contenido', () {
    final nombre = NombreEspacio.fromInput(' Terraza ');

    expect(nombre.value, 'Terraza');
  });

  test('rechaza nombres sin contenido', () {
    expect(() => NombreEspacio.fromInput('   '), throwsA(isA<ArgumentError>()));
  });
}
