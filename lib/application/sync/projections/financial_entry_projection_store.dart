import '../models/sync_event.dart';
import 'financial_entry_projection.dart';

/// Puerta de la proyección local de registros financieros. Provee la
/// transacción atómica y el evento de creación por id (idempotencia del
/// command service). No expone borrado: una incidencia de entrega nunca
/// elimina ni revierte un registro aplicado (contrato §6.5).
abstract interface class FinancialEntryProjectionStore {
  Future<T> atomic<T>(Future<T> Function() action);

  Future<FinancialEntryProjection?> findById(String id);

  /// Evento de creación del registro existente con `id`, o `null` si no
  /// existe registro local con esa identidad.
  Future<SyncEvent?> entryEvent(String id);

  Future<void> insert(FinancialEntryProjection projection);

  /// Avanza `last_server_sequence` del registro por `created_event_id` (echo).
  Future<void> advanceServerSequence(String eventId, int serverSequence);
}