import '../models/sync_event.dart';
import '../payloads/categoria_financiera_creada_payload.dart';
import '../projections/financial_category_projection.dart';
import '../projections/financial_category_projection_store.dart';

/// Handler idempotente de `categoria_financiera_creada` (contrato §7.1 y
/// §6.6). Reaplicar el mismo evento solo avanza `last_server_sequence`; una
/// colisión de identidad local sin reemplazo oficial lanza `StateError`; un
/// evento oficial con `serverSequence` reemplaza la alta local mediante upsert
/// (nunca `deleteCreatedByEvent`: la FK RESTRICT protege las entries).
class FinancialCategoryEventHandler {
  FinancialCategoryEventHandler(this._store);
  final FinancialCategoryProjectionStore _store;

  Future<void> apply(SyncEvent event) async {
    if (event.aggregateType != CategoriaFinancieraCreadaPayload.aggregateType ||
        event.eventType != CategoriaFinancieraCreadaPayload.eventType ||
        event.baseVersion != 1 ||
        event.baseServerSequence != null) {
      throw const FormatException('Sobre de categoría financiera inválido.');
    }
    final payload = CategoriaFinancieraCreadaPayload.fromJson(event.payload);
    final existing = await _store.findById(event.aggregateId);
    if (existing != null) {
      if (existing.createdEventId == event.eventId) {
        if (event.serverSequence != null) {
          await _store.advanceServerSequence(
            event.aggregateId,
            event.serverSequence!,
          );
        }
        return;
      }
      if (event.serverSequence == null ||
          existing.lastServerSequence != null ||
          existing.createdEventId == null) {
        throw StateError(
          'Ya existe una categoría financiera con id ${event.aggregateId}.',
        );
      }
      // El oficial convive con la alta local: el upsert reemplaza la
      // proyección conservando `financial_entries` que ya la referencian
      // (contrato §6.6 y §6.7).
    }
    await _store.insert(
      FinancialCategoryProjection(
        id: event.aggregateId,
        name: payload.name,
        direction: payload.direction.code,
        nature: payload.nature.code,
        active: true,
        version: 1,
        createdEventId: event.eventId,
        lastEventId: event.eventId,
        lastServerSequence: event.serverSequence,
      ),
    );
  }
}