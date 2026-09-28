import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/cuenta/account_balance_baseline.dart';
import '../../../domain/cuenta/saldo_cuenta_estimado.dart';
import '../../../domain/finanzas/transfer_summary.dart';
import '../../../domain/repositories/account_balance_baseline_repository.dart';
import '../../../domain/repositories/transfer_summary_repository.dart';
import '../cuenta/declarar_saldo_cuenta_screen.dart';
import 'block_figure.dart';
import 'cash_money.dart';

/// Bloque bancario como STOCK: cuanto hay en la cuenta ahora.
///
/// Convive con [TransferSummaryCard], que es el FLUJO del periodo. Son dos
/// numeros distintos y ambos se muestran: "cuanto movimos hoy" (flujo) y
/// "cuanto hay en la cuenta" (este bloque), cada uno con su etiqueta.
///
/// El estimado es la foto del banco (`SaldoCuentaEstimado`): saldo inicial
/// declarado mas entradas menos salidas con `occurred_at_ms > as_of_ms`. El
/// operador es `>` y no `>=`: un movimiento exactamente en `as_of_ms` ya esta
/// en la foto del banco y sumarlo seria duplicarlo. Un movimiento anterior a
/// `as_of_ms` queda fuera en silencio, y se cuenta en pantalla para que un
/// desplazamiento no sea invisible.
///
/// La conciliacion contra el estado de cuenta es EFIMERA: vive en el estado de
/// este widget mientras la pantalla esta abierta. No se escribe en ninguna
/// tabla, no se convierte en evento y no se guarda en preferencias: escribir
/// un saldo real del banco lo convertiria en un hecho, y un hecho persistido
/// seria un segundo saldo inicial (contradice D2).
///
/// El total combinado solo existe cuando el saldo inicial esta declarado y hay
/// un stock de efectivo que sumar: `expectedMinor` del turno abierto mas el
/// estimado. Sin baseline no hay total, hay aviso: nunca un total parcial
/// calculado con el flujo.
class SaldoCuentaEstimadoCard extends StatefulWidget {
  const SaldoCuentaEstimadoCard({
    super.key,
    required this.transfers,
    required this.baselines,
    this.expectedMinor,
    this.onDeclareTap,
  });

  final TransferSummaryRepository transfers;

  final AccountBalanceBaselineRepository baselines;

  /// Efectivo esperado del turno abierto de esta terminal, si lo hay. Solo con
  /// sesion abierta existe un stock de efectivo que pueda sumarse al estimado.
  final BigInt? expectedMinor;

  /// Accion «ir a declarar el saldo inicial». Por defecto abre
  /// [DeclararSaldoCuentaScreen].
  final VoidCallback? onDeclareTap;

  @override
  State<SaldoCuentaEstimadoCard> createState() =>
      _SaldoCuentaEstimadoCardState();
}

class _SaldoCuentaEstimadoCardState extends State<SaldoCuentaEstimadoCard> {
  StreamSubscription<AccountBalanceBaseline?>? _baselineSub;
  StreamSubscription<TransferSummary>? _movementsSub;

  AccountBalanceBaseline? _baseline;
  TransferSummary? _movements;
  bool _error = false;

  /// Fin de la ventana de movimientos, congelado al suscribirse: un `toMs` que
  /// se moviera en cada build reabriria el stream de Drift en cada
  /// reconstruccion de pantalla. El estimado es vivo en el sentido de que los
  /// movimientos posteriores a `as_of_ms` se leen en vivo; el borde superior
  /// de la ventana se refresca al resuscribirse, igual que el bloque de flujo.
  late int _toMs;

  /// Conciliacion efimera: el saldo del estado de cuenta que el usuario
  /// compara contra el estimado. Vive solo en memoria.
  int? _conciliacionMinor;
  bool _conciliacionInvalida = false;

  @override
  void initState() {
    super.initState();
    _toMs = DateTime.now().millisecondsSinceEpoch;
    _subscribeBaseline();
  }

  @override
  void didUpdateWidget(covariant SaldoCuentaEstimadoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.baselines != widget.baselines) {
      _baselineSub?.cancel();
      _movementsSub?.cancel();
      _movements = null;
      _toMs = DateTime.now().millisecondsSinceEpoch;
      _subscribeBaseline();
    } else if (oldWidget.transfers != widget.transfers) {
      _movementsSub?.cancel();
      _movements = null;
      _watchMovements(_baseline);
    }
  }

  @override
  void dispose() {
    _baselineSub?.cancel();
    _movementsSub?.cancel();
    super.dispose();
  }

  void _subscribeBaseline() {
    _baselineSub = widget.baselines.watchBaseline().listen(
      (baseline) {
        if (!mounted) return;
        setState(() {
          _baseline = baseline;
          _error = false;
        });
        _watchMovements(baseline);
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _baseline = null;
          _error = true;
        });
        _watchMovements(null);
      },
    );
  }

  /// Sin baseline no hay nada que sumar: ni estimado ni total, solo el aviso.
  /// Con baseline, la consulta pide todo el historial y el corte `> as_of_ms`
  /// lo aplica `SaldoCuentaEstimado`, no el SQL.
  void _watchMovements(AccountBalanceBaseline? baseline) {
    _movementsSub?.cancel();
    if (baseline == null) {
      setState(() => _movements = null);
      return;
    }
    _movementsSub = widget.transfers
        .watchTransferSummary(fromMs: 0, toMs: _toMs)
        .listen(
          (summary) {
            if (!mounted) return;
            setState(() {
              _movements = summary;
              _error = false;
            });
          },
          onError: (_) {
            if (!mounted) return;
            setState(() {
              _movements = null;
              _error = true;
            });
          },
        );
  }

  void _declarar() {
    final onTap = widget.onDeclareTap;
    if (onTap != null) {
      onTap();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const DeclararSaldoCuentaScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseline = _baseline;
    final movements = _movements;
    final estimado = baseline != null && movements != null
        ? SaldoCuentaEstimado.fromMovements(
            baseline: baseline,
            movements: movements.movements,
          )
        : null;

    return Card(
      key: const Key('saldo_cuenta_estimado_card'),
      margin: const EdgeInsets.only(top: 20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saldo en cuenta',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            if (_error)
              Text(
                'No se pudo consultar el saldo de la cuenta. El efectivo de '
                'arriba no se ve afectado.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              )
            else if (baseline == null)
              _aviso(theme)
            else if (estimado == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              )
            else
              _estimado(theme, estimado),
          ],
        ),
      ),
    );
  }

  /// Sin saldo inicial declarado: flujo aparte, aviso y forma de declararlo.
  /// Nunca un total parcial calculado con el flujo.
  Widget _aviso(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Todavía no se declara el saldo inicial de la cuenta.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Sin él no hay saldo estimado ni total en fondos: solo se muestra '
          'cuánto entró y salió por transferencia en el periodo.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          key: const Key('declarar_saldo_inicial'),
          onPressed: _declarar,
          icon: const Icon(Icons.account_balance),
          label: const Text('Declarar saldo inicial'),
        ),
      ],
    );
  }

  Widget _estimado(ThemeData theme, SaldoCuentaEstimado estimado) {
    final expected = widget.expectedMinor;
    final total = expected == null ? null : expected + estimado.estimatedMinor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BlockFigure(
          label: 'Saldo declarado al ${_stamp(estimado.baseline.asOfMs)}',
          value: cashMoney(BigInt.from(estimado.baseline.amountMinor)),
        ),
        const SizedBox(height: 8),
        Text(
          'Cubre todo lo anterior al ${_stamp(estimado.baseline.asOfMs)}; '
          'los movimientos posteriores se suman.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: BlockFigure(
                label: 'Entradas posteriores',
                value: cashMoney(estimado.incomeAfterAsOf),
              ),
            ),
            Expanded(
              child: BlockFigure(
                label: 'Salidas posteriores',
                value: cashMoney(estimado.expenseAfterAsOf),
              ),
            ),
          ],
        ),
        const Divider(height: 24),
        BlockFigure(
          label: 'Saldo estimado',
          value: cashMoney(estimado.estimatedMinor),
          destacado: true,
        ),
        const SizedBox(height: 8),
        Text(
          '${estimado.includedCount} movimientos posteriores a la foto · '
          '${estimado.excludedCount} anteriores ya estaban en la foto y no se '
          'suman.',
          style: theme.textTheme.bodySmall,
        ),
        const Divider(height: 24),
        _conciliacion(theme, estimado.estimatedMinor),
        if (total != null) ...[
          const Divider(height: 24),
          BlockFigure(
            label: 'Total en fondos (registrado)',
            value: cashMoney(total),
            destacado: true,
          ),
          const SizedBox(height: 4),
          Text(
            'Efectivo esperado del turno + saldo estimado. Son cifras de '
            'instantes distintos (el efectivo es del cierre del turno, el banco '
            'es de ahora): no es un saldo exacto ni utilidad.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  /// Comparacion de trabajo contra el estado de cuenta. EFIMERA: el valor vive
  /// en el estado del widget y no se persiste ni se convierte en evento.
  Widget _conciliacion(ThemeData theme, BigInt estimadoMinor) {
    final difference = _conciliacionMinor == null
        ? null
        : BigInt.from(_conciliacionMinor!) - estimadoMinor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Conciliación contra el estado de cuenta',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Compara el estimado con el saldo que reporta el banco. Es solo '
          'una comparación de trabajo: no se guarda.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('conciliacion_saldo_real'),
          initialValue: '',
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: InputDecoration(
            labelText: 'Saldo real del estado de cuenta (MXN)',
            hintText: '0.00',
            errorText: _conciliacionInvalida ? 'Captura un importe válido.' : null,
          ),
          onChanged: (value) => setState(() {
            final parsed = parseSignedMoney(value);
            _conciliacionMinor = parsed;
            _conciliacionInvalida =
                parsed == null && value.trim().isNotEmpty;
          }),
        ),
        if (difference != null) ...[
          const SizedBox(height: 8),
          Text(
            'Diferencia (real − estimado): ${cashMoney(difference)}',
            key: const Key('conciliacion_diferencia'),
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ],
    );
  }
}

String _stamp(int ms) =>
    '${DateTime.fromMillisecondsSinceEpoch(ms).toLocal()}';