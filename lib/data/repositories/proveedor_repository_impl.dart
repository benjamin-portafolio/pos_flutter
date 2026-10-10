import '../../domain/proveedores/proveedor.dart';
import '../../domain/repositories/proveedor_repository.dart';
import '../local/drift/app_database.dart';

class ProveedorRepositoryImpl implements ProveedorRepository {
  ProveedorRepositoryImpl(this._dao);
  final ProveedorDao _dao;

  @override
  Stream<List<Proveedor>> watchProveedores() => _dao.watchProveedores().map(
    (rows) => List.unmodifiable(
      rows.map(
        (row) => Proveedor(
          id: row.id,
          nombre: row.name,
          telefono: row.phone,
          notas: row.notes,
          version: row.version,
          createdEventId: row.createdEventId,
          lastEventId: row.lastEventId,
          lastServerSequence: row.lastServerSequence,
        ),
      ),
    ),
  );
}
