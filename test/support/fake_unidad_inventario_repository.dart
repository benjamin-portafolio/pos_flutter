import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/domain/inventario/unidad_inventario.dart';
import 'package:pos_flutter/domain/repositories/unidad_inventario_repository.dart';

const kgUnit = UnidadInventario(
  id: InventoryUnitIds.kilogram,
  code: 'kg',
  nombre: 'Kilogramo',
  simbolo: 'kg',
  dimension: DimensionUnidad.mass,
  factorAtomico: 1000,
  maximosDecimales: 3,
  activa: true,
);

class FakeUnidadInventarioRepository implements UnidadInventarioRepository {
  FakeUnidadInventarioRepository([
    List<UnidadInventario> units = const [kgUnit],
  ]) : _units = List.unmodifiable(units);

  final List<UnidadInventario> _units;

  @override
  Future<List<UnidadInventario>> obtenerUnidadesActivas() async => _units;

  @override
  Future<UnidadInventario?> obtenerUnidadPorId(String unidadId) async {
    for (final unit in _units) {
      if (unit.id == unidadId) return unit;
    }
    return null;
  }
}