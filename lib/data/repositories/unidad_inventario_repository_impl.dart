import '../../domain/inventario/dimension_unidad.dart';
import '../../domain/inventario/unidad_inventario.dart';
import '../../domain/repositories/unidad_inventario_repository.dart';
import '../local/drift/app_database.dart';

class UnidadInventarioRepositoryImpl implements UnidadInventarioRepository {
  UnidadInventarioRepositoryImpl({required UnitDao unitDao})
    : _unitDao = unitDao;

  final UnitDao _unitDao;

  @override
  Future<List<UnidadInventario>> obtenerUnidadesActivas() async {
    final rows = await _unitDao.obtenerUnidadesActivas();
    return rows.map(_toDomain).toList(growable: false);
  }

  @override
  Future<UnidadInventario?> obtenerUnidadPorId(String unidadId) async {
    final row = await _unitDao.obtenerUnidadPorId(unidadId);
    return row == null ? null : _toDomain(row);
  }

  UnidadInventario _toDomain(UnitRow row) => UnidadInventario(
    id: row.unitId,
    code: row.code,
    nombre: row.name,
    simbolo: row.symbol,
    dimension: DimensionUnidad.fromCode(row.dimension),
    factorAtomico: row.atomicFactor,
    maximosDecimales: row.maxFractionDigits,
    activa: row.active,
  );
}
