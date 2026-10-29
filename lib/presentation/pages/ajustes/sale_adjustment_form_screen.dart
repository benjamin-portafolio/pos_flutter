import '../caja/models/sale_draft_display.dart';
import '../../../core/di/injection.dart';
import '../../../domain/repositories/customer_account_repository.dart';
import 'package:flutter/material.dart';
import '../../../application/commands/ventas/prepare_sale_adjustment.dart';
import '../../../application/commands/ventas/sale_adjustment_command_service.dart';
import '../../../application/commands/ventas/anular_venta_command.dart';
import '../../../application/commands/ventas/registrar_devolucion_venta_command.dart';
import '../../../application/sync/payloads/venta_anulada_payload.dart';
import '../../../application/sync/payloads/devolucion_venta_registrada_payload.dart';
import '../../../application/sync/payloads/sale_adjustment_payload.dart';
import '../../../application/sync/payloads/venta_confirmada_payload.dart';
import '../../../domain/ventas/adjusted_sale.dart';
import '../informes/models/report_money.dart';
import 'return_lines_form.dart';
import 'void_settlement_form.dart';

/// Coordina preparación sin escritura, confirmación y commit. Devuelve el ID
/// confirmado; el caller abre el comprobante después de terminar el comando.
class SaleAdjustmentFormScreen extends StatefulWidget {
  const SaleAdjustmentFormScreen({
    super.key,
    required this.sale,
    required this.voidSale,
    required this.prepare,
  });
  final AdjustedSale sale;
  final bool voidSale;
  final PrepareSaleAdjustment prepare;
  @override
  State<SaleAdjustmentFormScreen> createState() =>
      _SaleAdjustmentFormScreenState();
}

class _SaleAdjustmentFormScreenState extends State<SaleAdjustmentFormScreen> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController(), _reference = TextEditingController();
  Map<String, ({int quantity, String destination})> _selections = {};
  String _action = 'refund_completed';
  String? _error;
  BigInt? _creditBalance;
  bool _busy = false, _declared = false;
  SaleAdjustmentPayload? _prepared;
  late final _recoverable = widget.prepare.commands.store.recoverableIntentions(
    widget.sale.original.id,
  );
  late final _original = widget.prepare.commands.store
      .confirmation(widget.sale.original.id)
      .then((e) => VentaConfirmadaPayload.fromJson(e!.payload));
  SaleAdjustmentCommandService get _commands => widget.prepare.commands;
  void _changed() => setState(() {
    _prepared = null;
    _error = null;
  });
  @override
  void dispose() {
    _reason.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _review() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await widget.prepare(
        saleId: widget.sale.original.id,
        expectedRevision: widget.sale.revision,
        voidSale: widget.voidSale,
        reason: _reason.text,
        action: _action,
        reference: _reference.text,
        selections: _selections,
      );
      BigInt? balance;
      if (widget.sale.original.isCredit &&
          getIt.isRegistered<CustomerAccountRepository>()) {
        final account = await getIt<CustomerAccountRepository>()
            .watchAccount(widget.sale.original.clienteId!)
            .first;
        balance = account.balanceMinor + BigInt.from(p.totalMinor);
      }
      if (mounted) {
        setState(() {
          _prepared = p;
          _creditBalance = balance;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commit() async {
    if (_busy || !_declared || _prepared == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final p = _prepared!;
    try {
      if (widget.voidSale) {
        await _commands.anular(
          AnularVentaCommand(
            payload: VentaAnuladaPayload.fromJson(p.toJson()),
            userId: _commands.context.userId,
            deviceId: _commands.context.deviceId,
          ),
        );
      } else {
        await _commands.devolver(
          RegistrarDevolucionVentaCommand(
            payload: DevolucionVentaRegistradaPayload.fromJson(p.toJson()),
            userId: _commands.context.userId,
            deviceId: _commands.context.deviceId,
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(p.operationId);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.voidSale ? 'Anular por error' : 'Registrar devolución',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Venta ${widget.sale.original.id}'),
                if (_prepared == null)
                  FutureBuilder(
                    future: _recoverable,
                    builder: (context, s) => Column(
                      children: [
                        for (final e in s.data ?? [])
                          if ((e.eventType == 'venta_anulada') ==
                              widget.voidSale)
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                      final p = SaleAdjustmentPayload.fromJson(
                                        e.payload,
                                      );
                                      _prepared = p;
                                      _reason.text = p.reason;
                                      _reference.text =
                                          p.settlement.reference ?? '';
                                      _action = p.settlement.action;
                                      _declared = false;
                                    }),
                              child: Text(
                                'Recuperar captura ${e.createdAtLocal.toLocal()}',
                              ),
                            ),
                      ],
                    ),
                  ),
                const Text('Se conserva la venta y su ticket original.'),
                if (widget.voidSale)
                  const Text(
                    'Anulación total: revierte ingreso y costo, y restituye exactamente los consumos históricos, incluidas recetas.',
                  ),
                if (!widget.voidSale)
                  FutureBuilder<VentaConfirmadaPayload>(
                    key: const ValueKey('return-lines'),
                    future: _original,
                    builder: (context, s) => s.hasData
                        ? ReturnLinesForm(
                            original: s.data!,
                            remaining: widget.sale.remainingQuantities,
                            enabled: !_busy && _prepared == null,
                            onChanged: (v) {
                              _selections = v;
                              _changed();
                            },
                          )
                        : const LinearProgressIndicator(),
                  ),
                TextFormField(
                  controller: _reason,
                  enabled: !_busy && _prepared == null,
                  decoration: const InputDecoration(
                    labelText: 'Motivo obligatorio',
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Indica el motivo.'
                      : null,
                  onChanged: (_) => _changed(),
                ),
                if (widget.voidSale && !widget.sale.original.isCredit)
                  VoidSettlementForm(
                    action: _action,
                    onChanged: _busy || _prepared != null
                        ? null
                        : (v) {
                            _action = v;
                            _changed();
                          },
                  ),
                if (widget.sale.original.paymentMethod == 'transfer')
                  TextFormField(
                    controller: _reference,
                    enabled: !_busy && _prepared == null,
                    decoration: const InputDecoration(
                      labelText: 'Referencia de devolución realizada',
                    ),
                    onChanged: (_) => _changed(),
                  ),
                if (widget.sale.original.isCredit)
                  const Text(
                    'Se reduce el cargo y se recalculan los abonos FIFO. Lo liberado cubre otras deudas o queda a favor; no se entrega efectivo.',
                  ),
                if (_prepared case final p?) ...[
                  const Divider(height: 32),
                  if (_creditBalance != null)
                    Text(
                      _creditBalance!.isNegative
                          ? 'Deuda total restante: ${ReportMoney.money(-_creditBalance!)}'
                          : 'Saldo a favor: ${ReportMoney.money(_creditBalance!)}',
                    ),
                  Text(
                    '${widget.sale.original.isCredit ? 'Reducción de deuda' : 'Importe del ajuste'}: ${ReportMoney.money(BigInt.from(p.totalMinor))}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    p.settlement.action == 'unreceived_correction'
                        ? 'Corrige un cobro no recibido; no declara devolución física. Si el faltante ya se contó, este ajuste afecta la conciliación actual sin cambiar el corte pasado.'
                        : p.settlement.action == 'credit_reduction'
                        ? 'El saldo a favor disponible se mostrará en la cuenta del cliente tras confirmar.'
                        : p.totalMinor == 0
                        ? 'Sin movimiento de dinero.'
                        : 'Reembolso realizado por el mismo método de la venta.',
                  ),
                  Text(
                    p.settlement.cash != null
                        ? 'Se registra en la caja abierta actual. Los cortes anteriores permanecen intactos.'
                        : 'Sin movimiento de cajón.',
                  ),
                  for (final l in p.lines)
                    Text(
                      '${widget.sale.original.items.singleWhere((i) => i.id == l.saleItemId).productName}: ${SaleDraftDisplay.measureNumber(l.quantityAtomic, widget.sale.original.items.singleWhere((i) => i.id == l.saleItemId).unitAtomicFactor ?? 1)} ${widget.sale.original.items.singleWhere((i) => i.id == l.saleItemId).unitSymbol ?? 'pzas'} · ${switch (l.destination) {
                        'void' => 'Restitución histórica',
                        'restock' => 'Reintegrar a existencias',
                        'not_restockable' => 'No reintegrable',
                        _ => 'Sin seguimiento',
                      }} · ${ReportMoney.money(BigInt.from(l.amountMinor))}',
                    ),
                  CheckboxListTile(
                    value: _declared,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _declared = v!),
                    title: const Text(
                      'Confirmo las consecuencias y la liquidación declarada.',
                    ),
                  ),
                  FilledButton(
                    onPressed: _busy || !_declared ? null : _commit,
                    child: Text(
                      widget.voidSale
                          ? 'Confirmar anulación'
                          : 'Confirmar devolución',
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _prepared = null;
                            _declared = false;
                          }),
                    child: const Text('Editar captura'),
                  ),
                ] else
                  FilledButton(
                    onPressed: _busy ? null : _review,
                    child: const Text('Revisar consecuencias'),
                  ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_busy) const LinearProgressIndicator(),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
