class RecuperarCotizacionResult {
  RecuperarCotizacionResult({
    required this.saleId,
    required this.eventId,
    required this.continued,
    required this.draftAvailable,
  });

  final String saleId;

  /// Null al continuar el origen, que no necesita un evento de recuperación.
  final String? eventId;
  final bool continued;

  /// Un reintento histórico devuelve su ID, pero no recrea una captura limpiada.
  final bool draftAvailable;
}
