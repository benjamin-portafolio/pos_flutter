import 'sync_projection.dart';

/// Proyección local de un registro financiero (`financial_entries`).
/// Conserva snapshots de la categoría al capturar y `direction`/`nature` como
/// códigos string; `lastServerSequence` solo avanza con el eco, sin reaplicar
/// importes (contrato §7.1).
class FinancialEntryProjection extends SyncProjection {
  const FinancialEntryProjection({
    required super.id,
    required this.categoryId,
    required this.categoryNameSnapshot,
    required this.direction,
    required this.nature,
    required this.amountMinor,
    required this.currency,
    required this.method,
    required this.occurredAtMs,
    required this.notes,
    required this.reference,
    required super.active,
    required super.version,
    required super.createdEventId,
    required super.lastEventId,
    required super.lastServerSequence,
  });

  final String categoryId;
  final String categoryNameSnapshot;
  final String direction;
  final String nature;
  final int amountMinor;
  final String currency;
  final String method;
  final int occurredAtMs;
  final String? notes;
  final String? reference;
}