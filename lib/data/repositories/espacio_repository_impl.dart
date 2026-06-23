import '../../domain/espacios/espacio.dart';
import '../../domain/repositories/espacio_repository.dart';
import '../local/drift/app_database.dart' as drift;

/// Implementation of the EspacioRepository for local read operations.
class EspacioRepositoryImpl implements EspacioRepository {
  final drift.EspacioDao _espacioDao;

  EspacioRepositoryImpl({required drift.EspacioDao espacioDao})
    : _espacioDao = espacioDao;

  @override
  Future<List<Espacio>> obtenerEspacios() async {
    final rows = await _espacioDao.obtenerEspacios();
    return rows.map(_toDomain).toList();
  }

  @override
  Stream<List<Espacio>> watchEspacios() {
    return _espacioDao.watchEspacios().map(
      (rows) => rows.map(_toDomain).toList(),
    );
  }

  Espacio _toDomain(drift.Espacio row) {
    return Espacio(
      id: row.id,
      nombre: row.nombre,
      identificacion: row.identificacion,
      visibilidad: row.visibilidad,
    );
  }
}
