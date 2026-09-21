class ClienteCreadoPayload {
  const ClienteCreadoPayload({required this.nombre, this.telefono});
  static const aggregateType = 'cliente';
  static const eventType = 'cliente_creado';
  final String nombre;
  final String? telefono;

  factory ClienteCreadoPayload.fromJson(Map<String, Object?> json) {
    final nombre = json['nombre'];
    final telefono = json['telefono'];
    if (nombre is! String || nombre.trim().isEmpty) {
      throw const FormatException('El nombre del cliente es obligatorio.');
    }
    if (telefono != null && telefono is! String) {
      throw const FormatException('El teléfono debe ser texto o null.');
    }
    final normalizedPhone = (telefono as String?)?.trim();
    return ClienteCreadoPayload(
      nombre: nombre.trim(),
      telefono: normalizedPhone == null || normalizedPhone.isEmpty
          ? null
          : normalizedPhone,
    );
  }
  Map<String, Object?> toJson() => {'nombre': nombre, 'telefono': telefono};
}
