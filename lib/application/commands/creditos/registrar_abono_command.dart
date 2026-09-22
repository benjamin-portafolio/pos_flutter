class RegistrarAbonoCommand {
  const RegistrarAbonoCommand({
    required this.id,
    required this.clienteId,
    required this.amountMinor,
    required this.method,
    this.reference,
  });

  /// Identidad estable de la captura, también al reintentar un guardado.
  final String id, clienteId, method;
  final int amountMinor;
  final String? reference;
}
