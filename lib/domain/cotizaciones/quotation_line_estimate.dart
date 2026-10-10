/// Lectura temporal de catálogo; nunca se persiste en quotation.
class QuotationLineEstimate {
  const QuotationLineEstimate({
    required this.quotationItemId,
    this.unitPriceMinor,
    this.priceReferenceQuantityAtomic,
    this.totalMinor,
    this.issue,
  });
  final String quotationItemId;
  final int? unitPriceMinor, priceReferenceQuantityAtomic, totalMinor;
  final String? issue;
}
