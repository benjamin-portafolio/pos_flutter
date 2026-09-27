import '../caja/caja_command_service.dart';
import 'package:uuid/uuid.dart';

import '../../sync/local_event_store.dart';
import '../../sync/models/sync_event.dart';
import '../../sync/payloads/inventory_movement_payload.dart';
import '../../sync/payloads/movimiento_financiero_registrado_payload.dart';
import '../../sync/projections/financial_category_projection_store.dart';
import '../../sync/projections/financial_entry_projection_store.dart';
import '../local_command_context.dart';
import 'registrar_movimiento_financiero_command.dart';

/// Comando de registro de ingreso/gasto adicional. Deriva snapshots y
/// `category_event_id` de la proyección de la categoría (sin red), rechaza
/// futuro por tolerancia de reloj (> now + 5 min), usa la identidad estable
/// del command para idempotencia y persiste evento+refs+proyección como una
/// sola transacción atómica. Devuelve el `event_id` creado o el previo en un
/// reintento idéntico.
class MovimientoFinancieroCommandService {
  MovimientoFinancieroCommandService({
    required this.store,
    required this.categories,
    required this.events,
    required this.context,
    this.cash,
  });

  final FinancialEntryProjectionStore store;
  final FinancialCategoryProjectionStore categories;
  final LocalEventStore events;
  final LocalCommandContext context;
  final CajaCommandService? cash;

  /// Tolerancia de reloj del command: `occurred_at_ms > now + 5 min` es
  /// inválido (contrato §2.4). Los payloads y el servidor solo validan el
  /// entero seguro.
  static const maxFutureToleranceMs = 5 * 60 * 1000;

  Future<String> registrar(RegistrarMovimientoFinancieroCommand command) =>
      store.atomic(() async {
        InventoryMovementPayload.requiredUuidV4(command.entryId, 'entry_id');
        final now = DateTime.now().millisecondsSinceEpoch;
        if (command.occurredAtMs > now + maxFutureToleranceMs) {
          throw StateError('La fecha del registro no puede ser futura.');
        }
        final category = await categories.findById(command.categoryId);
        if (category == null ||
            !category.active ||
            category.createdEventId == null) {
          throw StateError('La categoría del registro no está disponible.');
        }
        var payload = MovimientoFinancieroRegistradoPayload.fromJson({
          'category_id': command.categoryId,
          'category_event_id': category.createdEventId,
          'category_name_snapshot': category.name,
          'direction': category.direction,
          'nature': category.nature,
          'amount_minor': command.amountMinor,
          'currency': 'MXN',
          'method': command.method,
          'occurred_at_ms': command.occurredAtMs,
          'notes': command.notes,
          'reference': command.reference,
        });
        final previous = await store.entryEvent(command.entryId);
        if (previous != null) {
          final p = MovimientoFinancieroRegistradoPayload.fromJson(
            previous.payload,
          );
          if (p.categoryId != payload.categoryId ||
              p.categoryEventId != payload.categoryEventId ||
              p.categoryNameSnapshot != payload.categoryNameSnapshot ||
              p.direction != payload.direction ||
              p.nature != payload.nature ||
              p.amountMinor != payload.amountMinor ||
              p.currency != payload.currency ||
              p.method != payload.method ||
              p.occurredAtMs != payload.occurredAtMs ||
              p.notes != payload.notes ||
              p.reference != payload.reference ||
              (p.cash != null) != command.affectsDrawer) {
            throw StateError('Este registro ya se capturó con otros datos.');
          }
          return previous.eventId;
        }
        if (command.affectsDrawer &&
            (command.method != 'cash' || cash?.enabled != true)) {
          throw StateError('La caja requiere efectivo y captura habilitada.');
        }
        final binding = await cash?.binding(
          method: command.method,
          amountMinor: command.amountMinor,
          affectsDrawer: command.affectsDrawer,
        );
        payload = MovimientoFinancieroRegistradoPayload.fromJson({
          ...payload.toJson(),
          if (binding != null) 'cash': binding.toJson(),
        });
        final refs = payload.refs(command.entryId);
        if (context.userId.trim().isEmpty ||
            context.deviceId.trim().isEmpty ||
            refs.any((r) => r.refId.trim().isEmpty)) {
          throw StateError('Contexto inválido.');
        }
        final eventId = const Uuid().v4();
        await events.appendAndApply(
          SyncEvent(
            eventId: eventId,
            aggregateType: MovimientoFinancieroRegistradoPayload.aggregateType,
            aggregateId: command.entryId,
            eventType: MovimientoFinancieroRegistradoPayload.eventType,
            deviceId: context.deviceId,
            userId: context.userId,
            createdAtLocal: DateTime.now().toUtc(),
            baseVersion: 1,
            payload: payload.toJson(),
          ),
          refs: refs,
        );
        return eventId;
      });
}
