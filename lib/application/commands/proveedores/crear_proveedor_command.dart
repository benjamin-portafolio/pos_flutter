class CrearProveedorCommand {
  const CrearProveedorCommand({
    required this.nombre,
    this.telefono,
    this.notas,
  });
  final String nombre;
  final String? telefono;
  final String? notas;
}
