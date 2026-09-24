import 'package:flutter/material.dart';
import '../../../../domain/cobros/collection_entry.dart';
import '../models/report_period.dart';
import '../collection_movements_screen.dart';

class CollectionsReportCard extends StatelessWidget {
  const CollectionsReportCard({
    required this.collections,
    required this.period,
    super.key,
  });
  final Stream<List<CollectionEntry>> collections;
  final ReportPeriod period;
  static String _money(BigInt n) =>
      '\$${n ~/ BigInt.from(100)}.${(n % BigInt.from(100)).toString().padLeft(2, '0')} MXN';
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
          StreamBuilder<List<CollectionEntry>>(
            stream: collections,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text('No se pudieron cargar los cobros.');
              }
              if (!snapshot.hasData) return const CircularProgressIndicator();
              final entries = snapshot.data!.where(
                (e) => period.contains(e.date),
              );
              final cash = entries
                  .where((e) => e.method == 'cash')
                  .fold(BigInt.zero, (n, e) => n + BigInt.from(e.amountMinor));
              final transfer = entries
                  .where((e) => e.method == 'transfer')
                  .fold(BigInt.zero, (n, e) => n + BigInt.from(e.amountMinor));
              return Column(
                children: [
                  for (final row in <(String, String?, BigInt)>[
                    ('Efectivo', 'cash', cash),
                    ('Transferencia', 'transfer', transfer),
                    ('Total recibido', null, cash + transfer),
                  ])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(row.$1),
                      subtitle: Text(
                        _money(row.$3),
                        key: row.$2 == null
                            ? const Key('cobros_recibidos')
                            : ValueKey('cobros_${row.$2}'),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => CollectionMovementsScreen(
                            collections: collections,
                            initialEntries: snapshot.data!,
                            period: period,
                            method: row.$2,
                          ),
                        ),
                      ),
                    ),
                ],
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
