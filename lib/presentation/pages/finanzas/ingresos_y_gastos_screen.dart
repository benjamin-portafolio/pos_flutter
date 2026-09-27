import 'package:flutter/material.dart';

import '../../../application/commands/finanzas/categoria_financiera_command_service.dart';
import '../../../application/commands/finanzas/movimiento_financiero_command_service.dart';
import '../../../application/commands/finanzas/registrar_movimiento_financiero_command.dart';
import '../../../core/di/injection.dart';
import '../../../domain/finanzas/financial_category.dart';
import '../../../domain/finanzas/financial_direction.dart';
import '../../../domain/finanzas/financial_report.dart';
import '../../../domain/repositories/financial_category_repository.dart';
import '../../../domain/repositories/financial_entry_repository.dart';
import '../informes/models/report_period.dart';
import '../informes/report_date_filter_screen.dart';
import 'forms/movimiento_financiero_form_screen.dart';
import 'selector/financial_category_picker_screen.dart';
import 'widgets/financial_entries_summary.dart';
import 'widgets/financial_entry_card.dart';

/// Pantalla «Ingresos y gastos»: período, totales de **registros adicionales**
/// y lista reactiva de movimientos. Conecta selector de categorías por
/// dirección y formularios de registro a los command services reales.
///
/// Los totales no son utilidad ni saldo de caja: el resumen lo indica
/// expresamente (contrato §2.7). Toda lectura pasa por los repositorios de
/// dominio; esta pantalla no toca Drift.
class IngresosYGastosScreen extends StatefulWidget {
  const IngresosYGastosScreen({
    super.key,
    this.entryRepository,
    this.categoryRepository,
    this.categoryCommandService,
    this.movementCommandService,
    this.now,
  });

  final FinancialEntryRepository? entryRepository;
  final FinancialCategoryRepository? categoryRepository;
  final CategoriaFinancieraCommandService? categoryCommandService;
  final MovimientoFinancieroCommandService? movementCommandService;
  final DateTime Function()? now;

  @override
  State<IngresosYGastosScreen> createState() => _IngresosYGastosScreenState();
}

class _IngresosYGastosScreenState extends State<IngresosYGastosScreen> {
  late ReportPeriod _period = ReportPeriod.day(_now());
  late Stream<FinancialReport> _report = _watch();
  String? _method;

  FinancialEntryRepository get _entries =>
      widget.entryRepository ?? getIt<FinancialEntryRepository>();

  FinancialCategoryRepository get _categories =>
      widget.categoryRepository ?? getIt<FinancialCategoryRepository>();

  CategoriaFinancieraCommandService get _categoryCommands =>
      widget.categoryCommandService ??
      getIt<CategoriaFinancieraCommandService>();

  MovimientoFinancieroCommandService get _movementCommands =>
      widget.movementCommandService ??
      getIt<MovimientoFinancieroCommandService>();

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  Stream<FinancialReport> _watch() => _entries.watchFinancialReport(
    fromMs: _period.start.toUtc().millisecondsSinceEpoch,
    toMs: _period.endExclusive.toUtc().millisecondsSinceEpoch,
    method: _method,
  );

  void _applyPeriod(ReportPeriod period) {
    setState(() {
      _period = period;
      _report = _watch();
    });
  }

  Future<void> _selectPeriod() async {
    final selected = await Navigator.of(context).push<ReportPeriod>(
      MaterialPageRoute(
        builder: (_) =>
            ReportDateFilterScreen(initialPeriod: _period, today: _now()),
      ),
    );
    if (selected == null || !mounted) return;
    _applyPeriod(selected);
  }

  /// Flujo: botón Ingreso/Gasto → selector de categorías de esa dirección →
  /// si hay categoría, formulario de registro con el command service real.
  Future<void> _registrar(FinancialDirection direction) async {
    final category = await Navigator.of(context).push<FinancialCategory>(
      MaterialPageRoute(
        builder: (_) => FinancialCategoryPickerScreen(
          direction: direction,
          repository: _categories,
          commandService: _categoryCommands,
        ),
      ),
    );
    if (category == null || !mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MovimientoFinancieroFormScreen(
          cashEnabled: _movementCommands.cash?.enabled ?? false,
          category: category,
          now: widget.now,
          onSave: (result) => _movementCommands.registrar(
            RegistrarMovimientoFinancieroCommand(
              affectsDrawer: result.affectsDrawer,
              entryId: result.entryId,
              categoryId: result.categoryId,
              amountMinor: result.amountMinor,
              method: result.method,
              occurredAtMs: result.occurredAtMs,
              notes: result.notes,
              reference: result.reference,
            ),
          ),
        ),
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${direction.label} registrado y guardado. La lista se actualizó.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ingresos y gastos')),
      body: SafeArea(
        child: Column(
          children: [
            _periodSelector(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('boton_ingreso'),
                      onPressed: () => _registrar(FinancialDirection.income),
                      icon: const Icon(Icons.add),
                      label: const Text('Ingreso'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('boton_gasto'),
                      onPressed: () => _registrar(FinancialDirection.expense),
                      icon: const Icon(Icons.remove),
                      label: const Text('Gasto'),
                    ),
                  ),
                ],
              ),
            ),
            _methodFilter(),
            Expanded(
              child: StreamBuilder<FinancialReport>(
                stream: _report,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(
                      child: Text(
                        'No se pudieron cargar los registros adicionales.',
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final report = snapshot.data!;
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      FinancialEntriesSummaryCard(report: report),
                      if (report.entries.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'Sin registros adicionales en este período. '
                              'Usa los botones Ingreso o Gasto para registrar.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      for (final entry in report.entries)
                        FinancialEntryCard(entry: entry),
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

  Widget _periodSelector() {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Período anterior',
              onPressed: () => _applyPeriod(_period.shift(-1)),
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
              onPressed: () => _applyPeriod(_period.shift(1)),
              icon: const Icon(Icons.arrow_forward),
            ),
          ],
        ),
      ),
    );
  }

  Widget _methodFilter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SegmentedButton<String?>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: null, label: Text('Todos')),
          ButtonSegment(value: 'cash', label: Text('Efectivo')),
          ButtonSegment(value: 'transfer', label: Text('Transferencia')),
        ],
        selected: {_method},
        onSelectionChanged: (selection) {
          setState(() {
            _method = selection.first;
            _report = _watch();
          });
        },
      ),
    );
  }
}
