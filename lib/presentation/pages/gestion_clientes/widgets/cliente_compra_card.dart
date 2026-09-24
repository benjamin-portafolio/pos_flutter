import 'package:flutter/material.dart';

import '../../../../domain/ventas/confirmed_sale.dart';
import '../../caja/models/sale_draft_display.dart';
import '../../caja/models/sale_receipt_display.dart';

/// Tarjeta compacta de una compra (venta confirmada) en el detalle del cliente.
///
/// Muestra el cliente y la forma de pago como texto principal y
/// artículos/fecha/hora con menor énfasis; el id de la venta no se expone.
class ClienteCompraCard extends StatelessWidget {
  const ClienteCompraCard({required this.sale, this.onTap, super.key});

  final ConfirmedSale sale;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final receipt = SaleReceiptDisplay(sale);
    final paymentLabel = receipt.paymentLabel;
    final clientName = sale.clienteNombre;
    final articles = _articleCount(sale);
    final articlesLabel = articles == 1 ? '1 artículo' : '$articles artículos';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: theme.colorScheme.secondaryContainer,
                child: Icon(
                  Icons.receipt_long,
                  size: 20,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clientName == null
                          ? paymentLabel
                          : '$clientName por $paymentLabel',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$articlesLabel · ${receipt.date}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 144),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    SaleDraftDisplay.money(sale.totalMinor),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Artículos distintos de la venta, igual que el contador del borrador.
  static int _articleCount(ConfirmedSale sale) =>
      sale.items.map((item) => item.variantId).toSet().length;
}