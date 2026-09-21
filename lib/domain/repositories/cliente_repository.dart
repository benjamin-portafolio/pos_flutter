import '../clientes/cliente.dart';

abstract interface class ClienteRepository {
  Stream<List<Cliente>> watchClientes();
}
