import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/articulos/nombre_producto.dart';
import 'package:pos_flutter/domain/articulos/precio_venta.dart';

void main() {
  test('normaliza nombre con NFKC y espacios exteriores', () {
    expect(NombreProducto.fromInput('  Ｃａｆé  ').value, 'Café');
  });

  test('convierte importes decimales a unidad monetaria menor', () {
    expect(PrecioVenta.fromInput('50').unidadMenor, 5000);
    expect(PrecioVenta.fromInput('50.5').unidadMenor, 5050);
    expect(PrecioVenta.fromInput('50,05').unidadMenor, 5005);
  });

  test('rechaza cero y más de dos decimales', () {
    expect(() => PrecioVenta.fromInput('0'), throwsArgumentError);
    expect(() => PrecioVenta.fromInput('1.001'), throwsArgumentError);
  });
}
