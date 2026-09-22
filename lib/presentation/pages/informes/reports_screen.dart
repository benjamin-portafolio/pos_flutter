import '../../../domain/repositories/customer_account_repository.dart';
import 'widgets/collections_report_card.dart';
import 'package:flutter/material.dart';

import '../../../core/di/injection.dart';
import '../../../domain/repositories/confirmed_sale_repository.dart';
import '../../../domain/ventas/confirmed_sale.dart';
import 'models/report_period.dart';
import 'report_date_filter_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    this.repository,
    this.now,
    this.accountRepository,
  });

  final ConfirmedSaleRepository? repository;
  final CustomerAccountRepository? accountRepository;
  final DateTime Function()? now;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final _repository =
      widget.repository ?? getIt<ConfirmedSaleRepository>();
  late Stream<List<ConfirmedSale>> _sales = _repository.watchSales();
  late final _payments =
      (widget.accountRepository ??
              (getIt.isRegistered<CustomerAccountRepository>()
                  ? getIt<CustomerAccountRepository>()
                  : null))
          ?.watchPayments();
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
            // El repositorio conserva fecha e importe del cobro, incluso si
            // la entrega al servidor está pendiente o requiere atención.
            final total = snapshot.data!
                .where((sale) => _period.contains(sale.createdAt))
                .fold(
                  BigInt.zero,
                  (sum, sale) => sum + BigInt.from(sale.totalMinor),
                );
            final hundred = BigInt.from(100);
            final amount =
                '\$${total ~/ hundred}.${(total % hundred).toString().padLeft(2, '0')} MXN';
            return Column(
              children: [
                _ReportCard(
                  title: 'VENTAS TOTALES',
                  child: Text(
                    amount,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                if (_payments != null)
                  CollectionsReportCard(
                    payments: _payments,
                    sales: snapshot.data!,
                    period: _period,
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
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
