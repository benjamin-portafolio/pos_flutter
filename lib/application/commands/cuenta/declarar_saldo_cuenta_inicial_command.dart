class DeclararSaldoCuentaInicialCommand {
  const DeclararSaldoCuentaInicialCommand({
    required this.baselineId,
    required this.amountMinor,
  });

  /// Identidad estable del hecho, generada por la pantalla como en caja
  /// (`AbrirCajaCommand.sessionId`). Da idempotencia al reintento.
  final String baselineId;

  /// Saldo reportado por el banco, en centavos. Admite negativo: una cuenta
  /// sobregirada es una declaración legítima.
  final int amountMinor;
}
