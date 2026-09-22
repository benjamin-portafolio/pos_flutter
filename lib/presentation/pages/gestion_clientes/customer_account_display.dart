import '../../../domain/creditos/account_entry.dart';
import '../../../domain/creditos/customer_account.dart';

class CustomerAccountDisplay {
  static String money(BigInt value) {
    final n = value.abs(), h = BigInt.from(100);
    return '${value.isNegative ? '-' : ''}\$${n ~/ h}.${(n % h).toString().padLeft(2, '0')}';
  }

  static String status(AccountEntry e) => switch (e.deliveryStatus) {
    'not_required' => 'Registro local',
    'delivered' => 'Sincronizado',
    'conflict' || 'rejected' => 'Requiere atención',
    _ => 'Pendiente de sincronizar',
  };
  static String statement(
    String name,
    CustomerAccount account, {
    String? operationId,
  }) {
    // El ticket de la operación incluye deudas pendientes y las que liquidó.
    final previous = CustomerAccount(
      account.entries.where((e) => e.id != operationId),
    );
    final credits = account.entries
        .where(
          (e) =>
              !e.isPayment &&
              (account.pendingMinor(e) > 0 ||
                  (operationId != null &&
                      (e.id == operationId ||
                          previous.pendingMinor(e) > account.pendingMinor(e)))),
        )
        .toList();
    final creditIds = credits.map((e) => e.id).toSet();
    final paymentIds = account.allocations
        .where((a) => creditIds.contains(a.creditId))
        .map((a) => a.paymentId)
        .toSet();
    final shown = account.entries.where(
      (e) =>
          creditIds.contains(e.id) ||
          paymentIds.contains(e.id) ||
          e.id == operationId ||
          (e.isPayment && account.availableMinor(e) > 0),
    );
    return [
      'ESTADO DE CUENTA · MXN',
      name,
      'Emitido: ${DateTime.now().toLocal()}',
      'Saldo: ${money(account.balanceMinor)} (${account.balanceMinor.isNegative
          ? 'Debe'
          : account.balanceMinor == BigInt.zero
          ? 'Saldado'
          : 'A favor'})',
      '',
      for (final e in shown) ...[
        '${e.date} · ${e.isPayment ? 'Abono' : 'Venta a crédito'} · ${money(BigInt.from(e.amountMinor))}',
        'Folio: ${e.id}',
        if (!e.isPayment)
          'Pendiente: ${money(BigInt.from(account.pendingMinor(e)))}${account.pendingMinor(e) == 0 ? ' · Liquidada en esta operación' : ''}',
        if (e.isPayment)
          for (final a in account.allocations.where(
            (a) => a.paymentId == e.id && creditIds.contains(a.creditId),
          ))
            'Aplicado a ${a.creditId}: ${money(BigInt.from(a.amountMinor))}',
        status(e),
        if (e.reason != null) e.reason!,
        '',
      ],
    ].join('\n');
  }
}
