import 'package:flutter/material.dart';
import '../../../../domain/creditos/account_entry.dart';
import '../../../../domain/ventas/confirmed_sale.dart';
import '../models/report_period.dart';

/// Entradas reales: efectivo aplicado a ventas más abonos y anticipos,
/// excluyendo crédito otorgado y cambio entregado.
class CollectionsReportCard extends StatelessWidget {
  const CollectionsReportCard({
    required this.payments,
    required this.sales,
    required this.period,
    super.key,
  });
  final Stream<List<AccountEntry>> payments;
  final List<ConfirmedSale> sales;
  final ReportPeriod period;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'COBROS RECIBIDOS',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<AccountEntry>>(
            stream: payments,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text('No se pudieron cargar los cobros.');
              }
              if (!snapshot.hasData) return const CircularProgressIndicator();
              final cash = sales
                  .where((s) => !s.isCredit && period.contains(s.createdAt))
                  .fold(BigInt.zero, (n, s) => n + BigInt.from(s.totalMinor));
              final abonos = snapshot.data!
                  .where((p) => period.contains(p.date))
                  .fold(BigInt.zero, (n, p) => n + BigInt.from(p.amountMinor));
              final total = cash + abonos, h = BigInt.from(100);
              return Text(
                '\$${total ~/ h}.${(total % h).toString().padLeft(2, '0')} MXN',
                key: const Key('cobros_recibidos'),
                style: Theme.of(context).textTheme.headlineMedium,
              );
            },
          ),
          const Text(
            'Incluye abonos y anticipos; excluye ventas a crédito sin cobro.',
          ),
        ],
      ),
    ),
  );
}
