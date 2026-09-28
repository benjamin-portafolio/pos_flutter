import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/caja/cash_session.dart';
import '../../../domain/finanzas/transfer_summary.dart';
import '../../../domain/repositories/transfer_summary_repository.dart';
import 'block_figure.dart';
import 'cash_money.dart';

/// Periodos ofrecidos por el bloque de transferencias.
///
/// El corte de caja mide un turno; por eso el turno es el periodo por defecto
/// cuando hay caja abierta, y el día es el respaldo cuando no la hay. El fin
/// del periodo queda congelado al elegirlo: una ventana que se moviera sola
/// reabriría la consulta en cada reconstrucción de la pantalla.
enum TransferPeriodKind {
  shift('Turno actual'),
  today('Hoy');

  const TransferPeriodKind(this.label);
  final String label;
}

typedef _Window = ({TransferPeriodKind kind, int fromMs, int toMs});

/// Bloque de transferencias de la pantalla de caja.
///
/// Presenta el agregado de la Fase 1 como **movimiento del periodo**, nunca
/// como saldo. `CashSession.expectedMinor` es un stock: lo que hay en el
/// cajón ahora. El neto de transferencias es un flujo: lo que movió el banco
/// en el periodo. Son dos preguntas distintas y este bloque solo responde la
/// del flujo: no totaliza junto al de efectivo ni junto al saldo en cuenta, y
/// jamás debe hacerlo. El lado bancario como stock (saldo estimado) vive en
/// `SaldoCuentaEstimadoCard`, que es donde está el total combinado desde la
/// Fase 4, solo cuando el saldo inicial está declarado.
///
/// No se muestra chip de estado de entrega: la Fase 1 es solo lectura y
/// `TransferMovement` no expone `delivery_status`. No se inventa.
class TransferSummaryCard extends StatefulWidget {
  const TransferSummaryCard({
    super.key,
    required this.repository,
    this.session,
  });

  final TransferSummaryRepository repository;

  /// Sesión abierta de esta terminal, si la hay. Solo habilita el periodo
  /// «Turno actual»; el bloque no depende de ella para existir.
  final CashSession? session;

  @override
  State<TransferSummaryCard> createState() => _TransferSummaryCardState();
}

class _TransferSummaryCardState extends State<TransferSummaryCard> {
  StreamSubscription<TransferSummary>? _subscription;

  /// Elección explícita del usuario. `null` significa «el default de ahora».
  TransferPeriodKind? _chosen;

  /// Fin del periodo, congelado al abrir o al cambiar de periodo.
  late int _toMs;

  _Window? _window;
  TransferSummary? _summary;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _toMs = DateTime.now().millisecondsSinceEpoch;
    _listen();
  }

  @override
  void didUpdateWidget(covariant TransferSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _chosen = null;
      _toMs = DateTime.now().millisecondsSinceEpoch;
    }
    _listen();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  bool get _hasOpenShift => widget.session != null && !widget.session!.isClosed;

  /// El turno solo se ofrece con caja abierta; sin ella el periodo cae al día.
  TransferPeriodKind _resolveKind() {
    final chosen = _chosen;
    if (chosen != null &&
        (chosen != TransferPeriodKind.shift || _hasOpenShift)) {
      return chosen;
    }
    return _hasOpenShift ? TransferPeriodKind.shift : TransferPeriodKind.today;
  }

  /// Inicio del día local que contiene el fin congelado del periodo.
  int get _startOfToday {
    final end = DateTime.fromMillisecondsSinceEpoch(_toMs);
    return DateTime(end.year, end.month, end.day).millisecondsSinceEpoch;
  }

  _Window _resolveWindow() {
    final kind = _resolveKind();
    return (
      kind: kind,
      fromMs: kind == TransferPeriodKind.shift
          ? widget.session!.openedAtMs
          : _startOfToday,
      toMs: _toMs,
    );
  }

  void _listen() {
    final window = _resolveWindow();
    if (_window == window) return;
    _window = window;
    _summary = null;
    _error = false;
    _subscription?.cancel();
    _subscription = widget.repository
        .watchTransferSummary(fromMs: window.fromMs, toMs: window.toMs)
        .listen(
          (summary) {
            if (!mounted) return;
            setState(() {
              _summary = summary;
              _error = false;
            });
          },
          onError: (_) {
            if (!mounted) return;
            // Un fallo se dice. Dejar el spinner girando se leeria como
            // "cargando" para siempre y taparia que no sabemos nada.
            setState(() {
              _summary = null;
              _error = true;
            });
          },
        );
  }

  void _select(TransferPeriodKind kind) {
    setState(() {
      _chosen = kind;
      _toMs = DateTime.now().millisecondsSinceEpoch;
    });
    _listen();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final window = _window ?? _resolveWindow();
    final summary = _summary;

    return Card(
      key: const Key('transfer_summary_card'),
      margin: const EdgeInsets.only(top: 20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transferencias · movimiento del periodo',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            _periodSelector(window.kind),
            const SizedBox(height: 16),
            if (_error)
              Text(
                'No se pudo consultar el movimiento de transferencias. El '
                'efectivo de arriba no se ve afectado.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              )
            else if (summary == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              )
            else if (summary.isEmpty)
              Text(
                'Sin transferencias en el periodo (${window.kind.label}). Eso no '
                'dice que la cuenta esté en cero: el saldo de la cuenta se '
                'consulta en el bloque de abajo.',
                style: theme.textTheme.bodyMedium,
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: BlockFigure(
                      label: 'Entradas por transferencia',
                      value: cashMoney(summary.incomeMinor),
                    ),
                  ),
                  Expanded(
                    child: BlockFigure(
                      label: 'Salidas por transferencia',
                      value: cashMoney(summary.expenseMinor),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              BlockFigure(
                label: 'Neto del periodo',
                value: cashMoney(summary.netMinor),
                destacado: true,
              ),
              const SizedBox(height: 8),
              Text(
                '${summary.movements.length} transferencias registradas en el periodo.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            // Texto fijo, sin botón de cerrar: es la aclaración que impide leer
            // este bloque como un saldo.
            Text(
              'Esto es cuánto entró y salió por transferencia en el periodo. '
              'No es el saldo de la cuenta: el saldo estimado se muestra aparte, '
              'en el bloque de saldo en cuenta.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Un abono de un crédito a tu nombre sí suma, porque es dinero que '
              'recibiste. Lo que sale de tu cuenta resta, aunque del lado del '
              'cliente ese mismo pago sea un abono.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _periodSelector(TransferPeriodKind current) {
    final segments = <ButtonSegment<TransferPeriodKind>>[
      if (_hasOpenShift)
        const ButtonSegment(
          value: TransferPeriodKind.shift,
          label: Text('Turno actual'),
        ),
      const ButtonSegment(value: TransferPeriodKind.today, label: Text('Hoy')),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SegmentedButton<TransferPeriodKind>(
        showSelectedIcon: false,
        key: const Key('transfer_period_selector'),
        segments: segments,
        selected: {current},
        onSelectionChanged: (selection) => _select(selection.first),
      ),
    );
  }
}
