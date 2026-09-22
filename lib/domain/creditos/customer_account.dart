import 'account_entry.dart';
import 'credit_allocation.dart';

/// FIFO determinista sobre fecha UTC en milisegundos e identidad UUID.
/// Los mismos movimientos producen las mismas aplicaciones, sin importar
/// su orden de recepción. Anticipos disponibles se aplican a nuevas ventas.
class CustomerAccount {
  CustomerAccount(Iterable<AccountEntry> movements)
    : entries = List.unmodifiable(
        movements.toList()..sort(AccountEntry.compare),
      );
  final List<AccountEntry> entries;
  BigInt get balanceMinor => entries.fold(
    BigInt.zero,
    (sum, e) => sum + BigInt.from(e.isPayment ? e.amountMinor : -e.amountMinor),
  );
  List<CreditAllocation> get allocations {
    final credits = entries.where((e) => !e.isPayment).toList();
    final payments = entries.where((e) => e.isPayment).toList();
    final result = <CreditAllocation>[];
    var i = 0, used = 0;
    for (final payment in payments) {
      var available = payment.amountMinor;
      while (available > 0 && i < credits.length) {
        final pending = credits[i].amountMinor - used;
        final amount = available < pending ? available : pending;
        if (amount > 0) {
          result.add(CreditAllocation(payment.id, credits[i].id, amount));
        }
        available -= amount;
        used += amount;
        if (used == credits[i].amountMinor) {
          i++;
          used = 0;
        }
      }
    }
    return result;
  }

  int pendingMinor(AccountEntry credit) =>
      credit.amountMinor -
      allocations
          .where((a) => a.creditId == credit.id)
          .fold(0, (n, a) => n + a.amountMinor);
  int availableMinor(AccountEntry payment) =>
      payment.amountMinor -
      allocations
          .where((a) => a.paymentId == payment.id)
          .fold(0, (n, a) => n + a.amountMinor);
}
