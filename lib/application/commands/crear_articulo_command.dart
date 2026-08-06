class CrearArticuloCommand {
  const CrearArticuloCommand({
    required this.nombre,
    required this.precioVenta,
    this.categoriaId,
  });

  final String nombre;
  final String? categoriaId;
  final String precioVenta;
}
