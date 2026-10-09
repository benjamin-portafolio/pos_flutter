/// Permite ofrecer la consulta de la cotización existente sin crear otra.
class QuotationAlreadyLinkedException implements Exception {
  const QuotationAlreadyLinkedException(this.quotationId);
  final String quotationId;
  @override
  String toString() => 'La captura ya tiene la cotización $quotationId.';
}
