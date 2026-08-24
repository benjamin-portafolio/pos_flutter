import '../inventario/unidad_inventario.dart';

abstract interface class UnidadInventarioRepository {
  Future<List<UnidadInventario>> obtenerUnidadesActivas();

  Future<UnidadInventario?> obtenerUnidadPorId(String unidadId);
}
