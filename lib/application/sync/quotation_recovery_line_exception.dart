/// Identifica la línea que la futura UI debe explicar, sin perder el documento.
class QuotationRecoveryLineException implements Exception {
  const QuotationRecoveryLineException(this.quotationItemId, this.reason);
  final String quotationItemId, reason;
  @override
  String toString() => 'Línea $quotationItemId: $reason';
}
