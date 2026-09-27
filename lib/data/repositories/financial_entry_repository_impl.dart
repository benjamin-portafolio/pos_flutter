import 'package:drift/drift.dart';

import '../../domain/finanzas/financial_direction.dart';
import '../../domain/finanzas/financial_entry.dart';
import '../../domain/finanzas/financial_nature.dart';
import '../../domain/finanzas/financial_report.dart';
import '../../domain/repositories/financial_entry_repository.dart';
import '../local/drift/app_database.dart';

/// Informe local de registros financieros adicionales (contrato §8.1 y §8.3).
/// Une `financial_entries` con `events` por `created_event_id` para exponer
/// `delivery_status`/`rejection_reason`/`user_id`/`device_id`, incluyendo las
/// aplicadas con cualquier estado de entrega (pendientes e incidencias
/// visibles). Filtra `[fromMs, toMs)` sobre `occurred_at_ms` con `BigInt`.
class FinancialEntryRepositoryImpl implements FinancialEntryRepository {
  FinancialEntryRepositoryImpl(this.db);
  final AppDatabase db;

  @override
  Stream<FinancialReport> watchFinancialReport({
    required int fromMs,
    required int toMs,
    String? method,
    String? direction,
    String? categoryId,
  }) {
    final conditions = <String>[
      'e.occurred_at_ms >= ?',
      'e.occurred_at_ms < ?',
      "ev.application_status = 'applied'",
    ];
    final variables = <Variable>[
      Variable<int>(fromMs),
      Variable<int>(toMs),
    ];
    if (method != null) {
      conditions.add('e.method = ?');
      variables.add(Variable<String>(method));
    }
    if (direction != null) {
      conditions.add('e.direction = ?');
      variables.add(Variable<String>(direction));
    }
    if (categoryId != null) {
      conditions.add('e.category_id = ?');
      variables.add(Variable<String>(categoryId));
    }
    final query = '''
      SELECT e.id AS id,
             e.created_event_id AS event_id,
             e.category_id,
             e.category_name_snapshot,
             e.direction,
             e.nature,
             e.amount_minor,
             e.currency,
             e.method,
             e.occurred_at_ms,
             e.notes,
             e.reference,
             ev.user_id,
             ev.device_id,
             ev.delivery_status,
             ev.rejection_reason
      FROM financial_entries e
      JOIN events ev ON ev.event_id = e.created_event_id
      WHERE ${conditions.join(' AND ')}
      ORDER BY e.occurred_at_ms DESC, e.id
    ''';
    return db
        .customSelect(
          query,
          variables: variables,
          readsFrom: {db.financialEntries, db.events},
        )
        .watch()
        .map((rows) => FinancialReport.fromEntries(rows.map(_entry).toList()));
  }

  FinancialEntry _entry(QueryRow row) => FinancialEntry(
    id: row.read<String>('id'),
    eventId: row.read<String>('event_id'),
    categoryId: row.read<String>('category_id'),
    categoryNameSnapshot: row.read<String>('category_name_snapshot'),
    direction: FinancialDirection.fromCode(row.read<String>('direction')),
    nature: FinancialNature.fromCode(row.read<String>('nature')),
    amountMinor: row.read<int>('amount_minor'),
    currency: row.read<String>('currency'),
    method: row.read<String>('method'),
    occurredAtMs: row.read<int>('occurred_at_ms'),
    notes: row.readNullable<String>('notes'),
    reference: row.readNullable<String>('reference'),
    deliveryStatus: row.read<String>('delivery_status'),
    rejectionReason: row.readNullable<String>('rejection_reason'),
    userId: row.read<String>('user_id'),
    deviceId: row.read<String>('device_id'),
  );
}