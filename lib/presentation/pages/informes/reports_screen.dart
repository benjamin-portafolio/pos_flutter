import 'package:flutter/material.dart';

import '../../../core/di/injection.dart';
import '../../../domain/repositories/collection_repository.dart';
import '../../../domain/repositories/confirmed_sale_repository.dart';
import '../../../domain/ventas/confirmed_sale.dart';
import 'models/beneficio_bruto_report.dart';
import 'models/report_money.dart';
import 'models/report_period.dart';
import 'models/sales_reports_calculator.dart';
import 'report_date_filter_screen.dart';
import 'sales_by_method_screen.dart';
import 'widgets/collections_report_card.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    this.repository,
    this.now,
    this.collectionRepository,
  });

  final ConfirmedSaleRepository? repository;
  final CollectionRepository? collectionRepository;
  final DateTime Function()? now;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final _repository =
      widget.repository ?? getIt<ConfirmedSaleRepository>();
  late Stream<List<ConfirmedSale>> _sales = _repository.watchSales();
  late final _collections =
      (widget.collectionRepository ??
              (getIt.isRegistered<CollectionRepository>()
                  ? getIt<CollectionRepository>()
                  : null))
          ?.watchCollections();
  late ReportPeriod _period = ReportPeriod.day(_now());

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  Future<void> _selectPeriod() async {
    final selected = await Navigator.of(context).push<ReportPeriod>(
      MaterialPageRoute(
        builder: (_) =>
            ReportDateFilterScreen(initialPeriod: _period, today: _now()),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => _period = selected);
  }

  Future<void> _openSalesByMethod() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => SalesByMethodScreen(
        initialPeriod: _period,
        repository: widget.repository,
        now: widget.now,
        sales: _sales,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xffeeeeee),
    child: ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const _ReportCard(
          title: 'BAJO INVENTARIO DE EXISTENCIAS',
          child: Text('—'),
        ),
        const _ReportCard(title: 'EXISTENCIAS RESTANTES', child: Text('—')),
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
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
          ),
        ),
        StreamBuilder<List<ConfirmedSale>>(
          stream: _sales,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ReportCard(
                title: 'VENTAS TOTALES',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('No se pudieron cargar las ventas.'),
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
              return const _ReportCard(
                title: 'VENTAS TOTALES',
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: CircularProgressIndicator(),
                ),
              );
            }
            return _SalesIndicatorRow(
              gross: SalesReportsCalculator.grossProfit(_period, snapshot.data!),
              total: SalesReportsCalculator.ventasTotales(
                _period,
                snapshot.data!,
              ),
            );
          },
        ),
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: _openSalesByMethod,
              icon: const Icon(Icons.bar_chart),
              label: const Text('Ver ventas por método'),
            ),
          ),
        ),
        if (_collections != null)
          CollectionsReportCard(collections: _collections, period: _period),
      ],
    ),
  );
}

/// Beneficio bruto y ventas totales del mismo período, juntos: lado a lado en
/// tablet y apilados en teléfono.
class _SalesIndicatorRow extends StatelessWidget {
  const _SalesIndicatorRow({required this.gross, required this.total});
  final BeneficioBrutoReport gross;
  final BigInt total;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final cards = <Widget>[
        _BeneficioBrutoCard(report: gross),
        _ReportCard(
          title: 'VENTAS TOTALES',
          child: Text(
            ReportMoney.money(total),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ];
      if (constraints.maxWidth < 560) {
        return Column(
          children: [for (final card in cards) card],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: cards[i]),
          ],
        ],
      );
    },
  );
}

class _BeneficioBrutoCard extends StatelessWidget {
  const _BeneficioBrutoCard({required this.report});
  final BeneficioBrutoReport report;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (report.estado == BeneficioBrutoEstado.noDisponible) {
      return _ReportCard(
        title: report.titulo,
        child: const Text(
          'Las líneas de este período no registran el costo estándar.',
        ),
      );
    }
    final negative = report.profitMinor.isNegative;
    return _ReportCard(
      title: report.titulo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            report.monto!,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: negative
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
          ),
          if (report.detalleSinCosto != null) ...[
            const SizedBox(height: 4),
            Text(report.detalleSinCosto!),
          ],
          const SizedBox(height: 8),
          Text(
            'Calculado con el costo estándar registrado en la venta.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}