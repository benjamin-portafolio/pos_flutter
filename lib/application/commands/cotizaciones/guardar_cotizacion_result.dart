class GuardarCotizacionResult {
  const GuardarCotizacionResult({
    required this.quotationId,
    required this.eventId,
    required this.issuedAtLocal,
  });
  final String quotationId, eventId;
  final DateTime issuedAtLocal;
}
