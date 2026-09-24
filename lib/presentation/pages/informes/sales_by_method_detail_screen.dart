import 'package:flutter/material.dart';

import '../../../core/di/injection.dart';
import '../../../domain/repositories/confirmed_sale_repository.dart';
import '../../../domain/ventas/confirmed_sale.dart';
import '../caja/models/sale_draft_display.dart';
import '../caja/models/sale_receipt_display.dart';
import '../caja/sale_receipt_screen.dart';
import 'models/report_money.dart';
import 'models/report_period.dart';
import 'models/ventas_por_metodo_report.dart';

/// Ventas confirmadas del período que componen una categoría del desglose por
/// método. Cada venta abre su recibo conservado.
class SalesByMethodDetailScreen extends StatefulWidget {
  const SalesByMethodDetailScreen({
    required this.metodo,
    required this.label,
    required this.period,
    super.key,
    this.repository,
    this.sales,
  });

  final MetodoVenta metodo;
  final String label;
  final ReportPeriod period;
  final ConfirmedSaleRepository? repository;
  final Stream<List<ConfirmedSale>>? sales;

  @override
  State<SalesByMethodDetailScreen> createState() =>
      _SalesByMethodDetailScreenState();
}

class _SalesByMethodDetailScreenState extends State<SalesByMethodDetailScreen> {
  late Stream<List<ConfirmedSale>> _sales =
      widget.sales ??
      (widget.repository ?? getIt<ConfirmedSaleRepository>()).watchSales();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Ventas · ${widget.label}')),
    body: StreamBuilder<List<ConfirmedSale>>(
      stream: _sales,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('No se pudieron cargar las ventas.'),
                TextButton(
                  onPressed: () => setState(
                    () => _sales =
                        widget.sales ??
                        (widget.repository ??
                                getIt<ConfirmedSaleRepository>())
                            .watchSales(),
                  ),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final ventas = snapshot.data!
            .where(
              (sale) =>
                  widget.period.contains(sale.createdAt) &&
                  widget.metodo.matches(sale.paymentMethod),
            )
            .toList();
        if (ventas.isEmpty) {
          return const Center(child: Text('Sin ventas en este período'));
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                '${widget.period.label} · ${ventas.length} '
                '${ventas.length == 1 ? 'venta' : 'ventas'}',
              ),
            ),
            for (final sale in ventas) _SaleCard(sale: sale, label: widget.label),
          ],
        );
      },
    ),
  );
}

class _SaleCard extends StatelessWidget {
  const _SaleCard({required this.sale, required this.label});
  final ConfirmedSale sale;
  final String label;
  @override
  Widget build(BuildContext context) {
    final status = switch (sale.deliveryStatus) {
      'delivered' => 'Sincronizada',
      'conflict' || 'rejected' => 'Requiere atención',
      'not_required' => 'Registro local',
      _ => 'Pendiente de sincronizar',
    };
    final receipt = SaleReceiptDisplay(sale);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => SaleReceiptScreen(saleId: sale.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(status)),
                  Text(
                    ReportMoney.money(BigInt.from(sale.totalMinor)),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              Text('Método: $label'),
              if (sale.paymentReference != null)
                Text('Referencia: ${sale.paymentReference}'),
              Text(receipt.date),
              if (sale.clienteNombre != null)
                Text('Cliente: ${sale.clienteNombre}'),
              const Divider(),
              for (final item in sale.items)
                Text(
                  '${item.productName} ${item.variantName ?? ''} · '
                  '${SaleDraftDisplay.quantity(item)}'
                  '${item.quantity == null ? '' : ' pza'} · '
                  '${SaleDraftDisplay.money(item.totalMinor)}',
                ),
            ],
          ),
        ),
      ),
    );
  }
}