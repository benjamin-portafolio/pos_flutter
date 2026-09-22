class Cliente {
  const Cliente({
    required this.id,
    required this.nombre,
    required this.telefono,
    this.active = true,
  });
  final String id;
  final bool active;
  final String nombre;
  final String? telefono;
}
