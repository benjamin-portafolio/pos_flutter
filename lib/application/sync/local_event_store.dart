import 'models/sync_event.dart';

abstract interface class LocalEventStore {
  Future<void> appendAndApply(
    SyncEvent event, {
    required List<LocalEventRef> refs,
  });
}

/// Evento y referencias que deben guardarse y aplicarse como una sola unidad
/// de trabajo junto con otros elementos del mismo lote.
class LocalEventAppend {
  const LocalEventAppend({required this.event, required this.refs});

  final SyncEvent event;
  final List<LocalEventRef> refs;
}

/// Capacidad opcional para aplicar varios agregados en una única transacción.
abstract interface class LocalAtomicEventBatchStore {
  Future<void> appendAndApplyBatchAtomically(List<LocalEventAppend> entries);
}

extension LocalEventStoreBatch on LocalEventStore {
  /// Usa una transacción atómica cuando el adaptador la soporta. El fallback
  /// conserva compatibilidad con dobles de prueba sencillos.
  Future<void> appendAndApplyAll(List<LocalEventAppend> entries) async {
    final store = this;
    if (store is LocalAtomicEventBatchStore) {
      await (store as LocalAtomicEventBatchStore).appendAndApplyBatchAtomically(
        entries,
      );
      return;
    }
    for (final entry in entries) {
      await appendAndApply(entry.event, refs: entry.refs);
    }
  }
}

class LocalEventRef {
  const LocalEventRef({
    required this.refType,
    required this.refId,
    required this.relationship,
  });

  const LocalEventRef.affects({required String refType, required String refId})
    : this(refType: refType, refId: refId, relationship: 'affects');

  const LocalEventRef.requiresUnique({
    required String refType,
    required String refId,
  }) : this(refType: refType, refId: refId, relationship: 'requires_unique');

  const LocalEventRef.uses({required String refType, required String refId})
    : this(refType: refType, refId: refId, relationship: 'uses');

  final String refType;
  final String refId;
  final String relationship;
}
