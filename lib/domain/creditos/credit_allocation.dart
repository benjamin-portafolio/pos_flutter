/// Distribución reconstruible; no representa una entrada adicional de dinero.
class CreditAllocation {
  const CreditAllocation(this.paymentId, this.creditId, this.amountMinor);
  final String paymentId, creditId;
  final int amountMinor;
}
