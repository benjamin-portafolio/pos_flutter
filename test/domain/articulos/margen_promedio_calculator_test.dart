import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/articulos/margen_promedio_calculator.dart';

void main() {
  const calculadora = MargenPromedioCalculator();

  test('aplica margen sobre venta con un decimal exacto sin redondear', () {
    final margenes = calculadora.calcular([
      (
        grupoId: 'categoria',
        productoId: 'producto',
        precioVentaMenor: 1000,
        costoEstandarMenor: 675,
      ),
    ]);

    expect(margenes['categoria'], closeTo(32.5, 0.0001));
  });

  test('promedia primero las variantes del producto y luego los productos', () {
    final margenes = calculadora.calcular([
      (
        grupoId: 'categoria',
        productoId: 'p1',
        precioVentaMenor: 1000,
        costoEstandarMenor: 500,
      ),
      (
        grupoId: 'categoria',
        productoId: 'p1',
        precioVentaMenor: 2000,
        costoEstandarMenor: 1000,
      ),
      (
        grupoId: 'categoria',
        productoId: 'p2',
        precioVentaMenor: 1000,
        costoEstandarMenor: 900,
      ),
    ]);

    // P1: (50 + 50) / 2 = 50. P2: 10. Categoría: (50 + 10) / 2 = 30.
    // El promedio ponderado por variantes habría dado 36.666...
    expect(margenes['categoria'], closeTo(30, 0.0001));
  });

  test('cuenta cada producto una sola vez por agrupación', () {
    final margenes = calculadora.calcular([
      (
        grupoId: 'categoria',
        productoId: 'p1',
        precioVentaMenor: 1000,
        costoEstandarMenor: 500,
      ),
      (
        grupoId: 'categoria',
        productoId: 'p1',
        precioVentaMenor: 2000,
        costoEstandarMenor: 1000,
      ),
      (
        grupoId: 'otra-categoria',
        productoId: 'p1',
        precioVentaMenor: 1000,
        costoEstandarMenor: 0,
      ),
    ]);

    expect(margenes['categoria'], closeTo(50, 0.0001));
    expect(margenes['otra-categoria'], closeTo(100, 0.0001));
  });

  test('excluye costo desconocido y precio cero, e incluye costo cero', () {
    final margenes = calculadora.calcular([
      (
        grupoId: 'categoria',
        productoId: 'sin-costo',
        precioVentaMenor: 1000,
        costoEstandarMenor: null,
      ),
      (
        grupoId: 'categoria',
        productoId: 'costo-cero',
        precioVentaMenor: 1000,
        costoEstandarMenor: 0,
      ),
      (
        grupoId: 'categoria',
        productoId: 'precio-cero',
        precioVentaMenor: 0,
        costoEstandarMenor: 0,
      ),
    ]);

    expect(margenes['categoria'], closeTo(100, 0.0001));
  });

  test('conserva los márgenes negativos', () {
    final margenes = calculadora.calcular([
      (
        grupoId: 'categoria-negativa',
        productoId: 'p1',
        precioVentaMenor: 1000,
        costoEstandarMenor: 1200,
      ),
      (
        grupoId: 'categoria-mixta',
        productoId: 'p1',
        precioVentaMenor: 1000,
        costoEstandarMenor: 1200,
      ),
      (
        grupoId: 'categoria-mixta',
        productoId: 'p2',
        precioVentaMenor: 1000,
        costoEstandarMenor: 500,
      ),
    ]);

    expect(margenes['categoria-negativa'], closeTo(-20, 0.0001));
    expect(margenes['categoria-mixta'], closeTo(15, 0.0001));
  });

  test('no inventa datos para agrupaciones vacías', () {
    expect(calculadora.calcular(const []), isEmpty);
  });
}
