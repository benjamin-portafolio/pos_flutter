import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/inventory_quantity_codec.dart';
import 'package:pos_flutter/domain/inventario/unidad_inventario.dart';

void main() {
  const codec = InventoryQuantityCodec();
  const piece = UnidadInventario(
    id: 'piece',
    code: 'piece',
    nombre: 'Pieza',
    simbolo: 'pza',
    dimension: DimensionUnidad.count,
    factorAtomico: 1,
    maximosDecimales: 0,
    activa: true,
  );
  const kg = UnidadInventario(
    id: 'kg',
    code: 'kg',
    nombre: 'Kilogramo',
    simbolo: 'kg',
    dimension: DimensionUnidad.mass,
    factorAtomico: 1000,
    maximosDecimales: 3,
    activa: true,
  );
  const liter = UnidadInventario(
    id: 'l',
    code: 'l',
    nombre: 'Litro',
    simbolo: 'L',
    dimension: DimensionUnidad.volume,
    factorAtomico: 1000,
    maximosDecimales: 3,
    activa: true,
  );

  test('convierte kg y L a átomos sin usar double', () {
    expect(codec.parsePositiveAtomic('0.25', kg), 250);
    expect(codec.parsePositiveAtomic('1,5', liter), 1500);
    expect(codec.formatAtomic(-250, kg), '−0.25');
  });

  test('rechaza precisión no representable y fracciones de pieza', () {
    expect(
      () => codec.parsePositiveAtomic('0.0005', kg),
      throwsFormatException,
    );
    expect(
      () => codec.parsePositiveAtomic('0.5', piece),
      throwsFormatException,
    );
  });

  test('rechaza signos y cero porque la UI define la dirección', () {
    expect(() => codec.parsePositiveAtomic('-1', kg), throwsFormatException);
    expect(() => codec.parsePositiveAtomic('+1', kg), throwsFormatException);
    expect(() => codec.parsePositiveAtomic('0', kg), throwsFormatException);
  });

  test('acepta cero solo para capturas iniciales no negativas', () {
    expect(codec.parseNonNegativeAtomic('0.000', kg), 0);
    expect(codec.parseNonNegativeAtomic('0', piece), 0);
    expect(
      () => codec.parseNonNegativeAtomic('0.0000', kg),
      throwsFormatException,
    );
  });
}
