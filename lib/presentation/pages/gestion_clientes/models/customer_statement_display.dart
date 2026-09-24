import '../../../../domain/creditos/account_entry.dart';
import '../../../../domain/creditos/customer_account.dart';
import '../../../../domain/ventas/confirmed_sale.dart';
import '../../caja/models/sale_draft_display.dart';

/// Recibo que participa en el comprobante, con sus datos comerciales
/// tomados del recibo de venta original conservado.
class StatementReceipt {
  const StatementReceipt({
    required this.folio,
    required this.date,
    required this.itemRows,
    required this.totalMinor,
  });
  final String folio;
  final String date;
  final List<List<String>> itemRows;
  final int totalMinor;
}

/// Abono visible en el historial, agrupado por `payment_id`: cada pago
/// aparece una sola vez con la suma aplicada a los recibos del comprobante.
class StatementPayment {
  const StatementPayment({required this.date, required this.appliedMinor});
  final String date;
  final int appliedMinor;
}

/// Comprobante de estado de cuenta del cliente. La misma instancia alimenta
/// la vista previa y la imagen compartida, para que ambas muestren los mismos
/// datos y totales. No incluye UUIDs técnicos, dispositivos, usuarios ni
/// estados de sincronización: solo información comercial.
class CustomerStatement {
  CustomerStatement({
    required this.businessName,
    required this.clienteNombre,
    required this.issuedAt,
    required this.pendingReceipts,
    required this.liquidatedReceipts,
    required this.payments,
    required this.totalComprasMinor,
    required this.totalAbonadoMinor,
    required this.saldoPendienteMinor,
    required this.saldoFavorMinor,
  });
  final String? businessName;
  final String clienteNombre;
  final DateTime issuedAt;

  /// Recibos con saldo pendiente, del más antiguo al más reciente.
  final List<StatementReceipt> pendingReceipts;

  /// Recibos que solo quedaron en cero al aplicar el abono reciente.
  /// Solo existen en el comprobante de ese abono; no en consultas generales.
  final List<StatementReceipt> liquidatedReceipts;

  /// Abonos aplicados a los recibos incluidos, del más antiguo al más reciente.
  final List<StatementPayment> payments;
  final int totalComprasMinor;
  final int totalAbonadoMinor;
  final int saldoPendienteMinor;

  /// Dinero disponible a favor del cliente; siempre no negativo.
  final BigInt saldoFavorMinor;

  bool get isOperacionReciente => liquidatedReceipts.isNotEmpty;

  /// Construye el comprobante a partir de la cuenta del cliente y los recibos
  /// de venta originales. `operationId` identifica el abono recién registrado:
  /// cuando se provee, incluye además los recibos que quedaron liquidados por
  /// ese abono. Sin `operationId` es una consulta general que no arrastra
  /// recibos ya liquidados.
  static CustomerStatement build({
    required String clienteNombre,
    String? businessName,
    required CustomerAccount account,
    required List<ConfirmedSale> sales,
    String? operationId,
    DateTime? issuedAt,
  }) {
    final salesById = {for (final sale in sales) sale.id: sale};
    final previous = operationId == null
        ? null
        : CustomerAccount(account.entries.where((e) => e.id != operationId));

    // Recibos pendientes del más antiguo al más reciente.
    final pending = account.entries.where(
      (e) => !e.isPayment && account.pendingMinor(e) > 0,
    );
    // Créditos que tenían saldo pendiente antes del abono reciente y quedaron
    // en cero al aplicarlo. Un recibo liquidado por operaciones anteriores
    // tiene pendiente cero en `previous`, así que no entra aquí.
    final liquidated = previous == null
        ? const <AccountEntry>[]
        : account.entries.where(
            (e) =>
                !e.isPayment &&
                account.pendingMinor(e) == 0 &&
                previous.pendingMinor(e) > 0,
          );

    final documentCredits = [...pending, ...liquidated];
    final documentIds = documentCredits.map((e) => e.id).toSet();

    StatementReceipt receipt(AccountEntry credit) {
      final sale = salesById[credit.id];
      return StatementReceipt(
        folio: credit.id,
        date: sale == null ? date(credit.date) : date(sale.createdAt),
        itemRows: sale == null
            ? const []
            : [
                for (final item in sale.items)
                  [
                    [
                      item.productName,
                      if (item.variantName?.isNotEmpty ?? false)
                        item.variantName!,
                    ].join('\n'),
                    SaleDraftDisplay.price(item),
                    SaleDraftDisplay.quantity(item),
                    SaleDraftDisplay.money(item.totalMinor),
                  ],
              ],
        totalMinor: sale?.totalMinor ?? credit.amountMinor,
      );
    }

    // Historial de abonos: un pago aparece una sola vez con lo aplicado
    // exclusivamente a los créditos incluidos en este comprobante.
    final payments = <StatementPayment>[];
    for (final payment in account.entries.where((e) => e.isPayment)) {
      final applied = account.allocations
          .where(
            (a) =>
                a.paymentId == payment.id && documentIds.contains(a.creditId),
          )
          .fold(0, (sum, a) => sum + a.amountMinor);
      if (applied > 0) {
        payments.add(
          StatementPayment(date: date(payment.date), appliedMinor: applied),
        );
      }
    }

    final totalCompras = documentCredits.fold(0, (sum, e) => sum + e.amountMinor);
    final totalAbonado = account.allocations
        .where((a) => documentIds.contains(a.creditId))
        .fold(0, (sum, a) => sum + a.amountMinor);

    return CustomerStatement(
      businessName:
          businessName == null || businessName.trim().isEmpty
              ? null
              : businessName,
      clienteNombre: clienteNombre,
      issuedAt: issuedAt ?? DateTime.now(),
      pendingReceipts: pending.map(receipt).toList(),
      liquidatedReceipts: liquidated.map(receipt).toList(),
      payments: payments,
      totalComprasMinor: totalCompras,
      totalAbonadoMinor: totalAbonado,
      saldoPendienteMinor: totalCompras - totalAbonado,
      saldoFavorMinor:
          account.balanceMinor > BigInt.zero ? account.balanceMinor : BigInt.zero,
    );
  }

  /// MXN en centavos con separador de miles y dos decimales: `$1,500.00`.
  static String money(int minor) {
    final negative = minor < 0;
    final amount = minor.abs();
    final centavos = (amount % 100).toString().padLeft(2, '0');
    final pesos = (amount ~/ 100).toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '${negative ? '-' : ''}\$$pesos.$centavos';
  }

  /// Fecha local comprensible: `24/09/2026 10:30`.
  static String date(DateTime value) {
    final local = value.toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(local.day)}/${pad(local.month)}/${local.year} '
        '${pad(local.hour)}:${pad(local.minute)}';
  }
}