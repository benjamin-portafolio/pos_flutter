import 'package:uuid/uuid.dart';
import '../../sync/payloads/sale_adjustment_payload.dart';
import '../../sync/payloads/sale_adjustment_rules.dart';
import '../../sync/payloads/venta_confirmada_payload.dart';
import 'sale_adjustment_command_service.dart';
import '../../sync/projections/cash_projection_store.dart';

/// Prepara una intención congelada desde documentos históricos. No escribe.
class PrepareSaleAdjustment {
  PrepareSaleAdjustment(this.commands, this.cash);
  final SaleAdjustmentCommandService commands;
  final CashProjectionStore cash;

  Future<SaleAdjustmentPayload> call({
    required String saleId,
    required int expectedRevision,
    required bool voidSale,
    required String reason,
    required String action,
    String? reference,
    Map<String, ({int quantity, String destination})> selections = const {},
  }) async {
    if (await commands.store.hasIncident(saleId)) {
      throw StateError(
        'La venta tiene una incidencia pendiente de conciliación.',
      );
    }
    final confirmation = await commands.store.confirmation(saleId);
    if (confirmation == null) throw StateError('No se encontró la venta.');
    final original = VentaConfirmadaPayload.fromJson(confirmation.payload);
    final history = (await commands.store.history(
      saleId,
    )).map((e) => SaleAdjustmentPayload.fromJson(e.payload)).toList();
    if (history.length != expectedRevision) {
      throw StateError(
        'Cambió la venta. Cierra el formulario y revisa el remanente.',
      );
    }
    const uuid = Uuid();
    final lines = <Map<String, Object?>>[];
    for (final source in original.lines) {
      final s = source.snapshot;
      final q = s.quantity ?? s.measuredQuantityAtomic!;
      final selection = selections[source.id];
      if (!voidSale && selection == null) continue;
      final quantity = voidSale ? q : selection!.quantity;
      final destination = voidSale ? 'void' : selection!.destination;
      final previous = history
          .expand((h) => h.lines)
          .where((l) => l.saleItemId == source.id);
      final before = previous.fold(0, (n, l) => n + l.quantityAtomic);
      final recovered = previous
          .where((l) => l.destination == 'restock')
          .fold(0, (n, l) => n + l.quantityAtomic);
      final after =
          recovered + (voidSale || destination == 'restock' ? quantity : 0);
      int delta(int total) =>
          SaleAdjustmentRules.cumulative(total, after, q) -
          SaleAdjustmentRules.cumulative(total, recovered, q);
      final cost = SaleAdjustmentRules.historicalCostMinor(s);
      lines.add({
        'sale_item_id': source.id,
        'quantity_atomic': quantity,
        'destination': destination,
        'reason': destination == 'not_restockable' ? reason.trim() : null,
        'amount_minor':
            SaleAdjustmentRules.cumulative(s.totalMinor, before + quantity, q) -
            SaleAdjustmentRules.cumulative(s.totalMinor, before, q),
        'recovered_cost_minor': cost == null ? null : delta(cost),
        'stock': [
          for (final c in source.consumptions)
            if (delta(-c.deltaAtomic) > 0)
              {
                'movement_id': uuid.v4(),
                'original_movement_id': c.movementId,
                'inventory_item_id': c.inventoryItemId,
                'quantity_atomic': delta(-c.deltaAtomic),
              },
        ],
      });
    }
    final total = lines.fold(0, (n, l) => n + (l['amount_minor'] as int));
    final session =
        commands.config.config.cashEnabled &&
            original.paymentMethod == 'cash' &&
            total > 0
        ? await cash.current(commands.context.deviceId)
        : null;
    if (commands.config.config.cashEnabled &&
        original.paymentMethod == 'cash' &&
        total > 0 &&
        session == null) {
      throw StateError('Abre la caja actual antes de confirmar el ajuste.');
    }
    final now = DateTime.now();
    final p = SaleAdjustmentPayload.fromJson({
      'schema_version': 1,
      'kind': voidSale ? 'void' : 'return',
      'operation_id': uuid.v4(),
      'event_id': uuid.v4(),
      'sale_id': saleId,
      'confirmation_event_id': confirmation.eventId,
      'expected_revision': expectedRevision,
      'previous_adjustment_event_id': history.lastOrNull?.eventId,
      'occurred_at_ms': now.millisecondsSinceEpoch,
      'utc_offset_minutes': now.timeZoneOffset.inMinutes,
      'business_date':
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      'reason': reason.trim(),
      'currency': original.currency,
      'total_minor': total,
      'settlement': {
        'method': original.paymentMethod,
        'payment_id': original.paymentId,
        'cliente_id': original.clienteId,
        'action': original.isCredit
            ? 'credit_reduction'
            : total == 0
            ? 'no_money'
            : action,
        'reference': reference == null || reference.trim().isEmpty
            ? null
            : reference.trim(),
        'cash_enabled': commands.config.config.cashEnabled,
        'cash': session == null
            ? null
            : {
                'session_id': session.id,
                'opening_event_id': session.createdEventId,
                'movement_id': uuid.v4(),
              },
      },
      'lines': lines,
      'dependency_event_ids': [
        confirmation.eventId,
        if (history.isNotEmpty) history.last.eventId,
        if (session != null) session.createdEventId,
      ],
    });
    SaleAdjustmentRules.validate(
      p,
      original,
      confirmationEventId: confirmation.eventId,
      saleId: saleId,
      history: history,
    );
    return p;
  }
}
