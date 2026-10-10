import '../proveedores/proveedor.dart';

abstract interface class ProveedorRepository {
  Stream<List<Proveedor>> watchProveedores();
}
