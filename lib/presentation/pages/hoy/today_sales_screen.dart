import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/di/injection.dart';
import '../../../domain/repositories/confirmed_sale_repository.dart';
import '../../../domain/ventas/confirmed_sale.dart';
import '../caja/models/sale_receipt_display.dart';
import '../caja/sale_receipt_screen.dart';
import '../informes/models/report_money.dart';
import '../informes/models/report_period.dart';
import '../informes/models/sales_reports_calculator.dart';
import '../informes/models/ventas_por_metodo_report.dart';

/// Consulta las ventas locales conservadas, sin modificar sus cobros.
class TodaySalesScreen extends StatefulWidget {
  const TodaySalesScreen({this.repository, this.now, super.key});

  final ConfirmedSaleRepository? repository;
  final DateTime Function()? now;

  @override
  State<TodaySalesScreen> createState() => _TodaySalesScreenState();
}

class _TodaySalesScreenState extends State<TodaySalesScreen>
    with WidgetsBindingObserver {
  late final _repository =
      widget.repository ?? getIt<ConfirmedSaleRepository>();
  late Stream<List<ConfirmedSale>> _sales = _repository.watchSales();
  Timer? _dayTimer;
  MetodoVenta? _filter;

  DateTime _now() => (widget.now?.call() ?? DateTime.now()).toLocal();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleNextDay();
  }

  void _scheduleNextDay() {
    _dayTimer?.cancel();
    final now = _now();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    _dayTimer = Timer(nextDay.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _scheduleNextDay();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      _scheduleNextDay();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final period = ReportPeriod.day(_now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Hoy · ${period.label}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
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
                      const Text('No se pudieron cargar las ventas de hoy.'),
                      TextButton(
                        onPressed: () =>
                            setState(() => _sales = _repository.watchSales()),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final today =
                  SalesReportsCalculator.salesInPeriod(period, snapshot.data!)
                    ..sort((a, b) {
                      final byDate = b.createdAt.compareTo(a.createdAt);
                      return byDate != 0 ? byDate : a.id.compareTo(b.id);
                    });
              final report = SalesReportsCalculator.ventasPorMetodo(
                period,
                today,
              );
              final visible = today
                  .where((sale) => _filter?.matches(sale.paymentMethod) ?? true)
                  .toList();
              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    sliver: SliverList.list(
                      children: [
                        _DaySummary(report: report),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            ChoiceChip(
                              label: const Text('Todas'),
                              selected: _filter == null,
                              onSelected: (_) => setState(() => _filter = null),
                            ),
                            for (final category in report.categorias)
                              ChoiceChip(
                                label: Text(category.label),
                                selected: _filter == category.metodo,
                                onSelected: (_) =>
                                    setState(() => _filter = category.metodo),
                              ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            'Ventas recientes',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (visible.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Text(
                              today.isEmpty
                                  ? 'Todavía no hay ventas hoy.'
                                  : 'No hay ventas de este método hoy.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    sliver: SliverList.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final sale = visible[index];
                        return _SaleTile(
                          sale: sale,
                          onTap: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => SaleReceiptScreen(
                                saleId: sale.id,
                                repository: _repository,
                                returnButtonLabel: 'Volver a Hoy',
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DaySummary extends StatelessWidget {
  const _DaySummary({required this.report});

  final VentasPorMetodoReport report;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ventas del día'),
          const SizedBox(height: 4),
          Text(
            report.montoTotal,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          Text(
            '${report.salesCount} ${report.salesCount == 1 ? 'venta' : 'ventas'}',
          ),
          const Divider(height: 24),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              for (final category in report.categorias)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.metodo.esCredito ? 'A crédito' : category.label,
                    ),
                    Text(
                      ReportMoney.money(category.amountMinor),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _SaleTile extends StatelessWidget {
  const _SaleTile({required this.sale, required this.onTap});

  final ConfirmedSale sale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final receipt = SaleReceiptDisplay(sale);
    final local = sale.createdAt.toLocal();
    final hour =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    final count = receipt.distinctItems;
    return Card(
      child: ListTile(
        key: ValueKey('today-sale-${sale.id}'),
        onTap: onTap,
        title: Row(
          children: [
            Text(hour),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                ReportMoney.money(BigInt.from(sale.totalMinor)),
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${receipt.paymentLabel} · $count ${count == 1 ? 'producto' : 'productos'}'
          '\n${sale.clienteNombre ?? 'Público general'}',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
