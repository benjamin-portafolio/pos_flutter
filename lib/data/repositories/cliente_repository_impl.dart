import '../../domain/clientes/cliente.dart';
import '../../domain/repositories/cliente_repository.dart';
import '../local/drift/app_database.dart';

class ClienteRepositoryImpl implements ClienteRepository {
  ClienteRepositoryImpl(this._dao);
  final ClienteDao _dao;
  @override
  Stream<List<Cliente>> watchClientes() => _dao.watchClientes().map(
    (rows) => rows
        .map(
          (row) =>
              Cliente(id: row.id, nombre: row.nombre, telefono: row.telefono),
        )
        .toList(),
  );
}
