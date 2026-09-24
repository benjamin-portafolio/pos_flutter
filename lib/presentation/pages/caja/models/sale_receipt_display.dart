import '../../../../domain/ventas/confirmed_sale.dart';
import 'sale_draft_display.dart';

/// Datos de presentación tomados exclusivamente del cobro conservado.
class SaleReceiptDisplay {
  const SaleReceiptDisplay(this.sale);

  final ConfirmedSale sale;
  String get paymentLabel => switch (sale.paymentMethod) {
    'cash' => 'Efectivo',
    'transfer' => 'Transferencia',
    'credit' => 'Crédito',
    _ => throw StateError('Método desconocido: ${sale.paymentMethod}'),
  };

  int get distinctItems =>
      sale.items.map((item) => item.variantId).toSet().length;

  String get quantities => SaleDraftDisplay.receiptQuantities(sale.items);

  String get date {
    final local = sale.createdAt.toLocal();
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${pad(local.day)}/${pad(local.month)}/${local.year} '
        '${pad(local.hour)}:${pad(local.minute)}';
  }

  List<List<String>> get itemRows => [
    for (final item in sale.items)
      [
        [
          item.productName,
          if (item.variantName?.isNotEmpty ?? false) item.variantName!,
        ].join('\n'),
        SaleDraftDisplay.price(item),
        SaleDraftDisplay.quantity(item),
        SaleDraftDisplay.money(item.totalMinor),
      ],
  ];

  List<(String, String)> get totals => [
    ('Subtotal', SaleDraftDisplay.money(sale.totalMinor)),
    ('Total general', SaleDraftDisplay.money(sale.totalMinor)),
    if (sale.paymentMethod == 'transfer')
      ('Transferencia recibida', SaleDraftDisplay.money(sale.totalMinor)),
    if (sale.isCredit)
      ('Cargo a la cuenta', SaleDraftDisplay.money(sale.totalMinor)),
    if (sale.paymentMethod == 'cash')
      ('Efectivo recibido', SaleDraftDisplay.money(sale.receivedMinor)),
    if (sale.paymentMethod == 'cash')
      ('Cambio', SaleDraftDisplay.money(sale.changeMinor)),
  ];

  String get semanticLabel => [
    'Recibo ${sale.id}',
    'Fecha: $date',
    if (sale.paymentReference != null) 'Referencia: ${sale.paymentReference}',
    if (sale.clienteNombre != null) 'Cliente: ${sale.clienteNombre}',
    '$paymentLabel. $distinctItems productos diferentes. $quantities.',
    'Monto: ${SaleDraftDisplay.money(sale.totalMinor)} ${sale.currency}',
    for (final row in itemRows)
      '${row[0]}, precio ${row[1]}, cantidad ${row[2]}, importe ${row[3]}',
    for (final total in totals) '${total.$1}: ${total.$2}',
  ].join('\n');
}
