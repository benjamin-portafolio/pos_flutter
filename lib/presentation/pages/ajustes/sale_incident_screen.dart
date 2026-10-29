import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../application/commands/ventas/conciliar_operacion_venta_command.dart';
import '../../../application/commands/ventas/sale_reconciliation_command_service.dart';
import '../../../application/sync/models/sale_incident_details.dart';
import '../../../application/sync/payloads/operacion_venta_conciliada_payload.dart';
import '../../../application/sync/projections/sale_adjustment_store.dart';
import '../../../application/sync/projections/cash_projection_store.dart';
import '../informes/models/report_money.dart';

class SaleIncidentScreen extends StatefulWidget {
  const SaleIncidentScreen({
    super.key,
    required this.incidentId,
    required this.commands,
    required this.adjustments,
    required this.cash,
  });
  final String incidentId;
  final SaleReconciliationCommandService commands;
  final SaleAdjustmentStore adjustments;
  final CashProjectionStore cash;
  @override
  State<SaleIncidentScreen> createState() => _SaleIncidentScreenState();
}

class _SaleIncidentScreenState extends State<SaleIncidentScreen> {
  final _reason = TextEditingController();
  final _recoveries = <String, int>{};
  final _recoveryDates = <String, DateTime>{};
  late Future<SaleIncidentDetails?> _details = widget.commands.store.incident(
    widget.incidentId,
  );
  OperacionVentaConciliadaPayload? _prepared;
  bool _busy = false, _declared = false;
  String? _message;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _prepare(SaleIncidentDetails i) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.commands.ensureAvailable(refresh: true);
      if (_reason.text.trim().isEmpty) {
        throw StateError('Indica un motivo que justifique las diferencias.');
      }
      if (i.winnerEventId == null || i.officialBaseEventId == null) {
        throw StateError('Sincroniza para consultar el ganador oficial.');
      }
      final now = DateTime.now();
      final date =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final recovery = <Map<String, Object?>>[
        for (final r in i.recordedRecoveries) r.toJson(),
      ];
      for (final e in i.evidence) {
        final amount = _recoveries[e.effectId] ?? 0;
        if (amount < 0 || amount > e.delta.abs()) {
          throw StateError('Recuperación fuera de la diferencia conservada.');
        }
        if (amount == 0) continue;
        final session =
            e.ledger == 'cash' && widget.commands.config.config.cashEnabled
            ? await widget.cash.current(widget.commands.context.deviceId)
            : null;
        if (e.ledger == 'cash' &&
            widget.commands.config.config.cashEnabled &&
            session == null) {
          throw StateError(
            'Abre la caja actual para documentar la recuperación.',
          );
        }
        final when = _recoveryDates[e.effectId] ?? now;
        final recoveryDate =
            '${when.year.toString().padLeft(4, '0')}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
        recovery.add({
          ...e.toJson(),
          'effect_id': const Uuid().v4(),
          'delta': -e.delta.sign * amount,
          'occurred_at_ms': when.millisecondsSinceEpoch,
          'utc_offset_minutes': when.timeZoneOffset.inMinutes,
          'business_date': recoveryDate,
          'cash_session_id': session?.id,
          'opening_event_id': session?.createdEventId,
        });
      }
      final p = OperacionVentaConciliadaPayload.fromJson({
        'schema_version': 1,
        'operation_id': const Uuid().v4(),
        'event_id': const Uuid().v4(),
        'incident_id': i.id,
        'sale_id': i.saleId,
        'loser_event_id': i.loser.eventId,
        'winner_event_id': i.winnerEventId,
        'official_base_event_id': i.officialBaseEventId,
        'expected_revision': i.officialRevision,
        'occurred_at_ms': now.millisecondsSinceEpoch,
        'utc_offset_minutes': now.timeZoneOffset.inMinutes,
        'business_date': date,
        'reason': _reason.text.trim(),
        'preserved_effects': i.evidence.map((e) => e.toJson()).toList(),
        'recovery_effects': recovery,
      });
      await widget.commands.store.validate(
        p,
        deviceId: widget.commands.context.deviceId,
      );
      if (mounted) setState(() => _prepared = p);
    } catch (e) {
      if (mounted) setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseRecoveryDate(String id, DateTime earliest) async {
    final now = DateTime.now();
    final initial = _recoveryDates[id] ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(earliest.year, earliest.month, earliest.day),
      lastDate: now,
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted || time == null) return;
    setState(
      () => _recoveryDates[id] = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _commit() async {
    if (_busy || !_declared || _prepared == null) return;
    setState(() => _busy = true);
    try {
      final c = widget.commands;
      await c.conciliar(
        ConciliarOperacionVentaCommand(
          payload: _prepared!,
          userId: c.context.userId,
          deviceId: c.context.deviceId,
        ),
      );
      if (mounted) {
        setState(
          () => _message =
              'Conciliación registrada: ${_prepared!.operationId}. Pendiente de aceptación; la incidencia continúa abierta hasta recibirla.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _amount(String ledger, int delta) => ledger == 'stock'
      ? '$delta unidades atómicas'
      : ReportMoney.money(BigInt.from(delta));
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Incidencia de venta')),
      body: FutureBuilder<SaleIncidentDetails?>(
        future: _details,
        builder: (context, s) {
          if (s.hasError) {
            return Center(
              child: Text('No se pudo consultar la incidencia: ${s.error}'),
            );
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final i = s.data!;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  SelectableText(
                    'Venta: ${i.saleId}\nOperación local: ${i.loser.operationId}\nEvento local: ${i.loser.eventId}\nGanador oficial: ${i.winnerEventId ?? 'Pendiente de consultar'}\nRevisión oficial: ${i.officialBaseEventId == null ? 'No disponible' : i.officialRevision}\nCausa: ${i.reason}${i.blockedByEventId == null ? '' : ' · Dependencia: ${i.blockedByEventId}'}',
                  ),
                  if (i.winner case final w?)
                    Text(
                      'Operación oficial: ${w.operationId} · ${w.reason} · ${ReportMoney.money(BigInt.from(w.totalMinor))}',
                    ),
                  Text(
                    'Operación local: ${i.loser.reason} · ${ReportMoney.money(BigInt.from(i.loser.totalMinor))}',
                  ),
                  Text(
                    i.resolutionEventId == null
                        ? 'Incidencia abierta. Nuevas acciones suspendidas en esta terminal.'
                        : 'Resuelta por ${i.resolutionEventId}',
                  ),
                  const Text(
                    'El documento y los efectos locales se conservan. Reconocerlos no entrega dinero ni recibe mercancía otra vez.',
                  ),
                  for (final e in i.evidence)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${switch (e.ledger) {
                                'stock' => 'Existencias',
                                'cash' => 'Efectivo',
                                'credit' => 'Crédito',
                                _ => 'Transferencia',
                              }}: ${_amount(e.ledger, e.delta)}',
                            ),
                            SelectableText(
                              'Origen: ${e.effectId}\nDestino: ${e.targetId}\nFecha: ${e.businessDate}${e.cashSessionId == null ? '' : ' · Caja: ${e.cashSessionId}'}',
                            ),
                            TextButton(
                              onPressed: _busy || _prepared != null
                                  ? null
                                  : () => _chooseRecoveryDate(
                                      e.effectId,
                                      DateTime.fromMillisecondsSinceEpoch(
                                        e.occurredAtMs,
                                      ).toLocal(),
                                    ),
                              child: Text(
                                'Fecha de recuperación: ${_recoveryDates[e.effectId]?.toString() ?? 'actual al confirmar'}',
                              ),
                            ),
                            TextField(
                              enabled:
                                  !_busy &&
                                  _prepared == null &&
                                  i.resolutionEventId == null,
                              decoration: InputDecoration(
                                labelText: e.ledger == 'stock'
                                    ? 'Recuperación posterior realizada (unidades atómicas)'
                                    : 'Recuperación posterior realizada (centavos)',
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (v) => _recoveries[e.effectId] =
                                  v.trim().isEmpty ? 0 : int.tryParse(v) ?? -1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  FutureBuilder(
                    future: widget.adjustments.readDeliveryState(),
                    builder: (context, state) => state.hasData
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Libro registrado / oficial / diferencia local',
                              ),
                              for (final e in state.data!.inventory.entries)
                                Text(
                                  'Stock ${e.key}: ${e.value.recorded} / ${e.value.official} / ${e.value.localDifference}',
                                ),
                              for (final e in state.data!.cash.entries)
                                Text(
                                  'Caja ${e.key}: ${e.value.recorded} / ${e.value.official} / ${e.value.localDifference} centavos',
                                ),
                              for (final e
                                  in state.data!.creditReductions.entries)
                                Text(
                                  'Crédito ${e.key}: ${e.value.recorded} / ${e.value.official} / ${e.value.localDifference} centavos',
                                ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                  for (final attempt in i.attempts)
                    ListTile(
                      title: Text(
                        'Declaración ${attempt.createdAtLocal.toLocal()} · ${attempt.applicationStatus != 'applied' ? 'captura sin aplicar' : attempt.deliveryStatus}',
                      ),
                      subtitle: Text(
                        attempt.rejectionReason ?? attempt.eventId,
                      ),
                      trailing: TextButton(
                        onPressed: _busy || i.resolutionEventId != null
                            ? null
                            : () => setState(() {
                                _prepared =
                                    OperacionVentaConciliadaPayload.fromJson(
                                      attempt.payload,
                                    );
                                _reason.text = _prepared!.reason;
                                _declared = false;
                              }),
                        child: const Text('Recuperar declaración'),
                      ),
                    ),
                  TextField(
                    controller: _reason,
                    enabled:
                        !_busy &&
                        _prepared == null &&
                        i.resolutionEventId == null,
                    decoration: const InputDecoration(
                      labelText: 'Motivo y justificación de las diferencias',
                    ),
                  ),
                  if (i.resolutionEventId == null) ...[
                    if (_prepared == null)
                      FilledButton(
                        onPressed: _busy ? null : () => _prepare(i),
                        child: const Text('Revisar conciliación'),
                      ),
                    if (_prepared case final p?) ...[
                      Text(
                        'Reconocimiento independiente: ${p.preservedEffects.length} efectos. Recuperaciones declaradas: ${p.recoveryEffects.length}. No aumenta cantidades devueltas oficiales ni cambia cortes cerrados.',
                      ),
                      for (final r in p.recoveryEffects)
                        Text(
                          'Recuperación ${r.ledger}: ${_amount(r.ledger, r.delta)} · ${DateTime.fromMillisecondsSinceEpoch(r.occurredAtMs).toLocal()}${r.cashSessionId == null ? '' : ' · Caja ${r.cashSessionId}'}',
                        ),
                      CheckboxListTile(
                        value: _declared,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _declared = v!),
                        title: const Text(
                          'Justifico el exceso y confirmo únicamente las recuperaciones realizadas.',
                        ),
                      ),
                      FilledButton(
                        onPressed: _busy || !_declared ? null : _commit,
                        child: const Text('Registrar conciliación'),
                      ),
                    ],
                  ],
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _prepared = null;
                            _declared = false;
                            _details = widget.commands.store.incident(
                              widget.incidentId,
                            );
                          }),
                    child: const Text(
                      'Revisar nueva intención tras un rechazo',
                    ),
                  ),
                  if (_message != null) SelectableText(_message!),
                  if (_busy) const LinearProgressIndicator(),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _details = widget.commands.store.incident(
                              widget.incidentId,
                            );
                          }),
                    child: const Text('Consultar estado actualizado'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
