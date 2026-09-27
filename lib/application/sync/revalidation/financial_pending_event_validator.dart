import '../models/sync_event.dart';
import '../payloads/categoria_financiera_creada_payload.dart';
import '../payloads/movimiento_financiero_registrado_payload.dart';
import '../projections/financial_category_projection_store.dart';
import '../synced_event_history.dart';
import 'pending_conflict.dart';
import 'pending_event_validator.dart';

/// Revalidación financiera de pendientes (contrato §6.5 y §6.7): detecta una
/// categoría cuya identidad ya existe oficialmente con otro evento de creación,
/// y registros cuya categoría no se puede sincronizar (dependencia fallida,
/// no requerida o reemplazada oficialmente). Ninguno restaura de forma
/// destructiva: un hecho financiero nunca se borra ni revierte por una
/// incidencia de entrega (FK RESTRICT; no se reutilizan las restauraciones de
/// catálogo).
class FinancialPendingEventValidator implements PendingEventValidator {
  FinancialPendingEventValidator({
    FinancialCategoryProjectionStore? financialCategoryProjectionStore,
    required SyncedEventHistory syncedEventHistory,
  }) : _categories = financialCategoryProjectionStore,
       _history = syncedEventHistory;

  final FinancialCategoryProjectionStore? _categories;
  final SyncedEventHistory _history;

  @override
  Future<PendingConflict?> validate(
    SyncEvent event,
    Set<String> conflictedEventIds,
  ) async {
    return switch (event.eventType) {
      CategoriaFinancieraCreadaPayload.eventType =>
        await _categoriaCreadaConflict(event),
      MovimientoFinancieroRegistradoPayload.eventType =>
        await _registroDependenciaConflict(event, conflictedEventIds),
      _ => null,
    };
  }

  /// Colisión de identidad: ya existe una categoría oficial (u otra local) con
  /// este `aggregate_id` creada por un evento distinto.
  Future<PendingConflict?> _categoriaCreadaConflict(SyncEvent event) async {
    final store = _categories;
    if (store == null) return null;
    final existing = await store.findById(event.aggregateId);
    if (existing != null && existing.createdEventId != event.eventId) {
      return PendingConflict(
        'Ya existe una categoría financiera con id ${event.aggregateId}.',
      );
    }
    return null;
  }

  /// El registro espera la aceptación del evento de creación de la categoría
  /// (`category_event_id`, contrato §3.4). Si esa dependencia falta, quedó
  /// conflictiva/rechazada, se propaga un conflicto previo o la categoría fue
  /// reemplazada oficialmente con otro evento de creación, el registro no se
  /// puede sincronizar (el servidor respondería `financial_entry_dependency`).
  Future<PendingConflict?> _registroDependenciaConflict(
    SyncEvent event,
    Set<String> conflictedEventIds,
  ) async {
    final payload = MovimientoFinancieroRegistradoPayload.fromJson(
      event.payload,
    );
    for (final id in payload.dependencyEventIds) {
      if (conflictedEventIds.contains(id) || await _dependenciaFallida(id)) {
        return const PendingConflict(
          'Operación registrada: la categoría financiera no se puede sincronizar. Requiere atención.',
        );
      }
    }
    final category = await _categories?.findById(payload.categoryId);
    if (category != null &&
        category.createdEventId != null &&
        category.createdEventId != payload.categoryEventId) {
      return const PendingConflict(
        'Operación registrada: la categoría financiera no se puede sincronizar. Requiere atención.',
      );
    }
    return null;
  }

  Future<bool> _dependenciaFallida(String eventId) async {
    final dependency = await _history.eventById(eventId);
    return dependency == null ||
        dependency.deliveryStatus == 'conflict' ||
        dependency.deliveryStatus == 'rejected' ||
        dependency.deliveryStatus == 'not_required';
  }

  // El hecho financiero local permanece aplicado y visible con su motivo.
  @override
  Future<void> restore(SyncEvent event, PendingConflict conflict) async {}
}