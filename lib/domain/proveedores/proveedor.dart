/// Proveedor del catálogo local y base capturada para editarlo sin perder cambios.
class Proveedor {
  const Proveedor({
    required this.id,
    required this.nombre,
    this.telefono,
    this.notas,
    required this.version,
    required this.createdEventId,
    required this.lastEventId,
    required this.lastServerSequence,
  });

  final String id;
  final String nombre;
  final String? telefono;
  final String? notas;
  final int version;
  final String? createdEventId;
  final String? lastEventId;
  final int? lastServerSequence;
}
