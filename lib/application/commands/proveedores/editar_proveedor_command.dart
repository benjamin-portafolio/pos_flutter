import '../../../domain/proveedores/proveedor.dart';

class EditarProveedorCommand {
  const EditarProveedorCommand({
    required this.base,
    required this.nombre,
    this.telefono,
    this.notas,
  });

  /// Snapshot leído al abrir el formulario; no se reemplaza por la base actual.
  final Proveedor base;
  final String nombre;
  final String? telefono;
  final String? notas;
}
