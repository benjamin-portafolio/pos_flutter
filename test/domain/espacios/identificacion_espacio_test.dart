import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/espacios/identificacion_espacio.dart';

void main() {
  test('normaliza una identificacion con contenido', () {
    final identificacion = IdentificacionEspacio.fromOptionalInput(' piso_1 ');

    expect(identificacion?.value, 'piso_1');
  });

  test('convierte identificaciones vacias a null', () {
    expect(IdentificacionEspacio.fromOptionalInput(null), isNull);
    expect(IdentificacionEspacio.fromOptionalInput('   '), isNull);
  });
}
