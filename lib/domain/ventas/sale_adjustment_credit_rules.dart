/// FIFO oracle for net historical charges; does not mutate original debts/payments.
class SaleAdjustmentCreditRules {
  static Map<String, Object?> allocate(
    List<({String id, int occurredAtMs, int amountMinor, int reductionMinor})>
    charges,
    List<({String id, int occurredAtMs, int amountMinor})> payments,
  ) {
    void valid(int v) {
      if (v < 0 || v > 9007199254740991) {
        throw const FormatException('Crédito fuera de rango.');
      }
    }

    final cs = [...charges]
      ..sort(
        (a, b) => a.occurredAtMs != b.occurredAtMs
            ? a.occurredAtMs.compareTo(b.occurredAtMs)
            : a.id.compareTo(b.id),
      );
    final ps = [...payments]
      ..sort(
        (a, b) => a.occurredAtMs != b.occurredAtMs
            ? a.occurredAtMs.compareTo(b.occurredAtMs)
            : a.id.compareTo(b.id),
      );
    if (cs.map((c) => c.id).toSet().length != cs.length ||
        ps.map((p) => p.id).toSet().length != ps.length) {
      throw const FormatException('Identidad duplicada.');
    }
    for (final c in cs) {
      valid(c.amountMinor);
      valid(c.reductionMinor);
      valid(c.occurredAtMs);
      if (c.reductionMinor > c.amountMinor) {
        throw const FormatException('Reducción excesiva.');
      }
    }
    for (final p in ps) {
      valid(p.amountMinor);
      valid(p.occurredAtMs);
    }
    final remaining = cs
        .map((c) => BigInt.from(c.amountMinor - c.reductionMinor))
        .toList();
    final allocations = <Map<String, Object?>>[];
    var favor = BigInt.zero, i = 0;
    for (final p in ps) {
      var available = BigInt.from(p.amountMinor);
      while (available > BigInt.zero && i < cs.length) {
        final amount = available < remaining[i] ? available : remaining[i];
        if (amount > BigInt.zero) {
          allocations.add({
            'payment_id': p.id,
            'credit_id': cs[i].id,
            'amount_minor': amount.toInt(),
          });
        }
        available -= amount;
        remaining[i] -= amount;
        if (remaining[i] == BigInt.zero) i++;
      }
      favor += available;
    }
    final pending = remaining.fold(BigInt.zero, (a, b) => a + b);
    if (favor > BigInt.from(9007199254740991) ||
        pending > BigInt.from(9007199254740991)) {
      throw const FormatException('Saldo fuera de rango.');
    }
    return {
      'allocations': allocations,
      'outstanding_minor': pending.toInt(),
      'credit_balance_minor': favor.toInt(),
    };
  }
}
