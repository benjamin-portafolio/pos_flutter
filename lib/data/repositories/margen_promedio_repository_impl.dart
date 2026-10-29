import '../../domain/articulos/margen_promedio_calculator.dart';
import '../../domain/repositories/margen_promedio_repository.dart';
import '../local/drift/app_database.dart' as drift;

class MargenPromedioRepositoryImpl implements MargenPromedioRepository {
  MargenPromedioRepositoryImpl({required drift.ProductoDao productoDao})
    : _productoDao = productoDao;

  static const _calculadora = MargenPromedioCalculator();

  final drift.ProductoDao _productoDao;

  @override
  Stream<Map<String, double>> watchMargenPromedioPorCategoria() {
    return _productoDao.watchMargenPromedioPorCategoria().map(_calcular);
  }

  @override
  Stream<Map<String, double>> watchMargenPromedioPorProveedor() {
    return _productoDao.watchMargenPromedioPorProveedor().map(_calcular);
  }

  Map<String, double> _calcular(List<drift.MargenPromedioVarianteRow> rows) {
    return _calculadora.calcular(
      rows.map(
        (row) => (
          grupoId: row.grupoId,
          productoId: row.productoId,
          precioVentaMenor: row.precioVentaMenor,
          costoEstandarMenor: row.costoEstandarMenor,
        ),
      ),
    );
  }
}
