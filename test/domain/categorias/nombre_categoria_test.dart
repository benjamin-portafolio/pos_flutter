import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/categorias/nombre_categoria.dart';

void main() {
  test('normaliza un nombre de categoría con contenido', () {
    final nombre = NombreCategoria.fromInput(' Bebidas ');

    expect(nombre.value, 'Bebidas');
  });

  test('rechaza nombres de categoría vacíos', () {
    expect(
      () => NombreCategoria.fromInput('   '),
      throwsA(isA<ArgumentError>()),
    );
  });
}
