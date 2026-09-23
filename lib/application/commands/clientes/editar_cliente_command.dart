class EditarClienteCommand {
  const EditarClienteCommand({
    required this.clienteId,
    required this.baseEventId,
    required this.nombre,
    this.telefono,
  });
  final String clienteId;
  final String baseEventId;
  final String nombre;
  final String? telefono;
}
