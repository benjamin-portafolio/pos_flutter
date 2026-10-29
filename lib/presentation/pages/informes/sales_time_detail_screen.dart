import 'package:flutter/material.dart';

import '../../../domain/repositories/confirmed_sale_repository.dart';
import '../../../domain/ventas/confirmed_sale.dart';
import '../caja/sale_receipt_screen.dart';
import 'models/report_money.dart';
import 'models/report_period.dart';
import 'models/sales_time_bucket.dart';
import 'models/sales_time_grouping.dart';

/// Detalle reactivo de las operaciones que componen un grupo del reporte.
class SalesTimeDetailScreen extends StatelessWidget {
  const SalesTimeDetailScreen({
    required this.period,
    required this.grouping,
    required this.bucketKey,
    required this.repository,
    required this.sales,
    super.key,
  });

  final ReportPeriod period;
  final SalesTimeGrouping grouping;
  final int bucketKey;
  final ConfirmedSaleRepository repository;
  final Stream<List<ConfirmedSale>> sales;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(grouping.bucketLabel(bucketKey))),
    body: StreamBuilder<List<ConfirmedSale>>(
      stream: sales,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('No se pudieron cargar las ventas.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final matches = SalesTimeBucket.calculate(
          period,
          snapshot.data!,
          grouping,
        ).where((bucket) => bucket.key == bucketKey);
        if (matches.isEmpty) {
          return const Center(child: Text('Sin operaciones en este grupo'));
        }
        final bucket = matches.single;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(period.label),
            ListTile(
              title: const Text('Ventas netas'),
              trailing: Text(ReportMoney.signedMoney(bucket.totalMinor)),
            ),
            for (final sale in bucket.sales)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long),
                  title: Text('Venta ${sale.id}'),
                  subtitle: Text(
                    [
                      '${ReportPeriod.formatDate(sale.createdAt.toLocal())} '
                          '${TimeOfDay.fromDateTime(sale.createdAt.toLocal()).format(context)}',
                      switch (sale.paymentMethod) {
                        'cash' => 'Efectivo',
                        'transfer' => 'Transferencia',
                        'credit' => 'Crédito',
                        'card' => 'Tarjeta',
                        _ => 'Otros métodos',
                      },
                      if (sale.clienteNombre != null) sale.clienteNombre!,
                    ].join(' · '),
                  ),
                  trailing: Text(
                    ReportMoney.signedMoney(BigInt.from(sale.totalMinor)),
                  ),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => SaleReceiptScreen(
                        saleId: sale.id,
                        repository: repository,
                        returnButtonLabel: 'Volver al reporte',
                      ),
                    ),
                  ),
                ),
              ),
            for (final adjustment in bucket.adjustments)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.undo),
                  title: Text('Ajuste · ${adjustment.businessDate}'),
                  subtitle: Text(
                    '${adjustment.reason} · Venta ${adjustment.saleId}',
                  ),
                  trailing: Text(
                    ReportMoney.signedMoney(
                      -BigInt.from(adjustment.amountMinor),
                    ),
                  ),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => SaleReceiptScreen(
                        saleId: adjustment.saleId,
                        repository: repository,
                        returnButtonLabel: 'Volver al reporte',
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
