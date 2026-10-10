import '../../../../domain/cotizaciones/quotation.dart';
import '../../../../domain/cotizaciones/quotation_item.dart';
import '../../../../domain/cotizaciones/quotation_estimate.dart';
import '../../../../domain/cotizaciones/quotation_status.dart';
import '../../../../application/tickets/ticket_document.dart';
import '../../caja/models/sale_draft_display.dart';

/// Combina selección durable y estimación temporal, sin persistir importes.
class QuotationDisplay {
  const QuotationDisplay(this.quotation, this.estimate);
  final Quotation quotation;
  final QuotationEstimate estimate;

  static const legend = 'No representa un pago ni reserva existencias';
  static const recoveryNotice = 'El precio se recalcula al recuperar en Caja';
  static const currentPrices = 'Precios vigentes al generar';

  String get status => switch (quotation.status) {
    QuotationStatus.disponible => 'Disponible',
    QuotationStatus.enVenta => 'En venta',
    QuotationStatus.vendida => 'Vendida',
  };

  String get date => _date(quotation.issuedAtLocal);
  String get calculatedAt => _date(estimate.calculatedAt, seconds: true);

  String _date(DateTime value, {bool seconds = false}) {
    final local = value.toLocal();
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${pad(local.day)}/${pad(local.month)}/${local.year} '
        '${pad(local.hour)}:${pad(local.minute)}'
        '${seconds ? ':${pad(local.second)}' : ''}';
  }

  String get total => estimate.totalMinor == null
      ? 'Total no disponible'
      : '${SaleDraftDisplay.money(estimate.totalMinor!)} ${estimate.currency}';

  List<List<String>> get itemRows => [
    for (final item in quotation.items) _row(item),
  ];
  List<String> _row(QuotationItem item) {
    final price = estimate.lines
        .where((line) => line.quotationItemId == item.id)
        .firstOrNull;
    final unitPrice = price?.unitPriceMinor;
    return [
      [
        item.productName,
        if (item.variantName?.isNotEmpty ?? false) item.variantName!,
        if (price?.issue != null) price!.issue!,
      ].join('\n'),
      unitPrice == null
          ? 'Precio no disponible'
          : item.quantity != null
          ? SaleDraftDisplay.money(unitPrice)
          : '${SaleDraftDisplay.money(unitPrice)} / ${SaleDraftDisplay.measureNumber(price!.priceReferenceQuantityAtomic!, item.unitAtomicFactor!)} ${item.unitSymbol}',
      item.quantity != null
          ? '${item.quantity}'
          : '${SaleDraftDisplay.measureNumber(item.measuredQuantityAtomic!, item.unitAtomicFactor!)} ${item.unitSymbol}',
      price?.totalMinor == null
          ? 'Importe no disponible'
          : SaleDraftDisplay.money(price!.totalMinor!),
    ];
  }

  TicketDocument get ticket => TicketDocument(
    title: 'COTIZACIÓN',
    identifier: 'Cotización # ${quotation.id}',
    date: date,
    dateLabel: 'Fecha de creación',
    currency: estimate.currency,
    details: [currentPrices, 'Cálculo: $calculatedAt', recoveryNotice],
    itemRows: itemRows,
    totals: [
      (
        'Total estimado actual',
        estimate.totalMinor == null
            ? 'Total no disponible'
            : SaleDraftDisplay.money(estimate.totalMinor!),
      ),
    ],
    footer: legend,
  );

  String get semanticLabel => [
    'COTIZACIÓN ${quotation.id}',
    'Fecha de creación: $date',
    currentPrices,
    'Cálculo: $calculatedAt',
    recoveryNotice,
    'Moneda: ${estimate.currency}',
    for (final row in itemRows)
      '${row[0]}, precio ${row[1]}, cantidad ${row[2]}, importe ${row[3]}',
    'Total estimado actual: $total',
    legend,
  ].join('\n');
}
