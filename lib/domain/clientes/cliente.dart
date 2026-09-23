class Cliente {
  const Cliente({
    required this.id,
    required this.nombre,
    required this.telefono,
    this.active = true,
    this.lastEventId,
  });
  final String id;
  final String? lastEventId;
  final bool active;
  final String nombre;
  final String? telefono;
}
