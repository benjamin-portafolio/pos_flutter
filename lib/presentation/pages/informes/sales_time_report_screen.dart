import 'package:flutter/material.dart';

import '../../../domain/repositories/confirmed_sale_repository.dart';
import '../../../domain/ventas/confirmed_sale.dart';
import 'models/report_money.dart';
import 'models/report_period.dart';
import 'models/sales_time_bucket.dart';
import 'models/sales_time_grouping.dart';
import 'report_date_filter_screen.dart';
import 'sales_time_detail_screen.dart';

/// Comparación temporal de ventas locales con acceso a sus tickets.
class SalesTimeReportScreen extends StatefulWidget {
  const SalesTimeReportScreen({
    required this.initialPeriod,
    required this.repository,
    this.now,
    super.key,
  });

  final ReportPeriod initialPeriod;
  final ConfirmedSaleRepository repository;
  final DateTime Function()? now;

  @override
  State<SalesTimeReportScreen> createState() => _SalesTimeReportScreenState();
}

class _SalesTimeReportScreenState extends State<SalesTimeReportScreen> {
  late ReportPeriod _period = widget.initialPeriod;
  late Stream<List<ConfirmedSale>> _sales = widget.repository.watchSales();
  SalesTimeGrouping _grouping = SalesTimeGrouping.hour;

  Future<void> _selectPeriod() async {
    final selected = await Navigator.of(context).push<ReportPeriod>(
      MaterialPageRoute(
        builder: (_) => ReportDateFilterScreen(
          initialPeriod: _period,
          today: widget.now?.call() ?? DateTime.now(),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => _period = selected);
  }

  void _openBucket(SalesTimeBucket bucket) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => SalesTimeDetailScreen(
        period: _period,
        grouping: _grouping,
        bucketKey: bucket.key,
        repository: widget.repository,
        sales: widget.repository.watchSales(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: SalesTimeGrouping.values.length,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Reporte de ventas'),
        bottom: TabBar(
          isScrollable: true,
          onTap: (index) =>
              setState(() => _grouping = SalesTimeGrouping.values[index]),
          tabs: [
            for (final grouping in SalesTimeGrouping.values)
              Tab(text: grouping.label),
          ],
        ),
      ),
      body: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Período anterior',
                onPressed: () => setState(() => _period = _period.shift(-1)),
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: _selectPeriod,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(_period.label, textAlign: TextAlign.center),
                ),
              ),
              IconButton(
                tooltip: 'Período siguiente',
                onPressed: () => setState(() => _period = _period.shift(1)),
                icon: const Icon(Icons.arrow_forward),
              ),
            ],
          ),
          Expanded(
            child: StreamBuilder<List<ConfirmedSale>>(
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
                            () => _sales = widget.repository.watchSales(),
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
                final buckets = SalesTimeBucket.calculate(
                  _period,
                  snapshot.data!,
                  _grouping,
                );
                final total = buckets.fold(
                  BigInt.zero,
                  (sum, bucket) => sum + bucket.totalMinor,
                );
                final max = buckets.fold(
                  BigInt.zero,
                  (max, bucket) => bucket.totalMinor.abs() > max
                      ? bucket.totalMinor.abs()
                      : max,
                );
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('VENTAS NETAS'),
                            Text(
                              ReportMoney.signedMoney(total),
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const Text(
                              'Ventas confirmadas menos devoluciones y anulaciones del período.',
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (buckets.isEmpty)
                      const ListTile(title: Text('Sin ventas en este período'))
                    else ...[
                      _TimeBarChart(
                        buckets: buckets,
                        max: max,
                        onTap: _openBucket,
                      ),
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Ordenado de mayor a menor venta neta. Toca un grupo para ver sus operaciones.',
                        ),
                      ),
                      if (_grouping == SalesTimeGrouping.hour)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'Los ajustes se incluyen por fecha de negocio y hora local de registro.',
                          ),
                        ),
                      for (final bucket in buckets)
                        Card(
                          child: ListTile(
                            title: Text(bucket.label),
                            subtitle: Text(
                              '${bucket.sales.length} ventas · ${bucket.adjustments.length} ajustes',
                            ),
                            trailing: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  ReportMoney.signedMoney(bucket.totalMinor),
                                ),
                                Text(
                                  total <= BigInt.zero
                                      ? '—'
                                      : '${ReportMoney.percentOf(bucket.totalMinor, total).toStringAsFixed(1)}%',
                                ),
                              ],
                            ),
                            onTap: () => _openBucket(bucket),
                          ),
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _TimeBarChart extends StatelessWidget {
  const _TimeBarChart({
    required this.buckets,
    required this.max,
    required this.onTap,
  });
  final List<SalesTimeBucket> buckets;
  final BigInt max;
  final ValueChanged<SalesTimeBucket> onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 220,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final bucket in buckets)
                SizedBox(
                  width: 108,
                  child: Semantics(
                    label:
                        '${bucket.label}: ${ReportMoney.signedMoney(bucket.totalMinor)}',
                    button: true,
                    child: InkWell(
                      onTap: () => onTap(bucket),
                      child: Column(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor: max == BigInt.zero
                                    ? 0
                                    : (bucket.totalMinor.abs() *
                                                  BigInt.from(1000) ~/
                                                  max)
                                              .toDouble() /
                                          1000,
                                widthFactor: 0.55,
                                child: ColoredBox(
                                  color: bucket.totalMinor.isNegative
                                      ? Theme.of(context).colorScheme.error
                                      : Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            ReportMoney.signedMoney(bucket.totalMinor),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            bucket.label,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
