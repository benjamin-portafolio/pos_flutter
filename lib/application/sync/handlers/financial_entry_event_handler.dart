import 'cash_event_handler.dart';
import '../models/sync_event.dart';
import '../payloads/movimiento_financiero_registrado_payload.dart';
import '../projections/financial_category_projection_store.dart';
import '../projections/financial_entry_projection.dart';
import '../projections/financial_entry_projection_store.dart';

/// Handler idempotente de `movimiento_financiero_registrado` (contrato §7.1 y
/// §6.4). Reaplicar el mismo evento solo avanza `last_server_sequence` (por
/// `created_event_id`); una colisión de identidad o una categoría no
/// disponible/referencia distinta a su evento de creación lanzan `StateError`
/// y la transacción del lote revierte (sin filas parciales). No modifica la
/// categoría ni su versión.
class FinancialEntryEventHandler {
  FinancialEntryEventHandler(this._store, this._categories, {this.cash});
  final CashEventHandler? cash;
  final FinancialEntryProjectionStore _store;
  final FinancialCategoryProjectionStore _categories;

  Future<void> apply(SyncEvent event) async {
    if (event.aggregateType !=
            MovimientoFinancieroRegistradoPayload.aggregateType ||
        event.eventType != MovimientoFinancieroRegistradoPayload.eventType ||
        event.baseVersion != 1 ||
        event.baseServerSequence != null) {
      throw const FormatException('Sobre de registro financiero inválido.');
    }
    final payload = MovimientoFinancieroRegistradoPayload.fromJson(
      event.payload,
    );
    final existing = await _store.findById(event.aggregateId);
    if (existing != null) {
      if (existing.createdEventId == event.eventId) {
        if (event.serverSequence != null) {
          await _store.advanceServerSequence(
            event.eventId,
            event.serverSequence!,
          );
        }
        return;
      }
      throw StateError('Identidad de registro financiero ya registrada.');
    }
    final category = await _categories.findById(payload.categoryId);
    if (category == null ||
        !category.active ||
        category.createdEventId == null ||
        category.createdEventId != payload.categoryEventId) {
      throw StateError('La categoría del registro no está disponible.');
    }
    if (category.direction != payload.direction.code ||
        category.nature != payload.nature.code) {
      // Mismo motivo canónico que el conflicto `financial_entry_snapshot`
      // del servidor para no mantener variantes Dart/TypeScript.
      throw StateError(
        'La clasificación del registro no coincide con la categoría oficial.',
      );
    }
    await _store.insert(
      FinancialEntryProjection(
        id: event.aggregateId,
        categoryId: payload.categoryId,
        categoryNameSnapshot: payload.categoryNameSnapshot,
        direction: payload.direction.code,
        nature: payload.nature.code,
        amountMinor: payload.amountMinor,
        currency: payload.currency,
        method: payload.method,
        occurredAtMs: payload.occurredAtMs,
        notes: payload.notes,
        reference: payload.reference,
        active: true,
        version: 1,
        createdEventId: event.eventId,
        lastEventId: event.eventId,
        lastServerSequence: event.serverSequence,
      ),
    );
    if (payload.cash != null) {
      if (cash == null) throw StateError('Falta el receptor de caja.');
      await cash!.record(
        event,
        payload.cash,
        sourceType: 'financial_entry',
        sourceId: event.aggregateId,
        amountMinor: payload.amountMinor,
        direction: payload.direction.code,
      );
    }
  }
}
