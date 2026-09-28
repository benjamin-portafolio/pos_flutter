import 'package:drift/drift.dart';

import '../../domain/finanzas/financial_direction.dart';
import '../../domain/finanzas/transfer_summary.dart';
import '../../domain/repositories/transfer_summary_repository.dart';
import '../local/drift/app_database.dart';
import '../local/drift/money_movements_sql.dart';

/// Agregación local de transferencias para el saldo estimado de la cuenta
/// bancaria. Consulta pura: no emite eventos, no crea sesión y no toca caja.
///
/// Extiende la forma compartida de `money_movements_sql.dart` (H1) con la
/// tercera rama, `financial_entries`, que es donde entran ingresos y egresos
/// (H1a). El filtro `method = 'transfer'` es el único filtro de medio porque las
/// tres tablas comparten el mismo CHECK (H2), y la aplicación se filtra por
/// evento, igual que en el informe de cobros (H3). `credit_allocations` no se
/// une: es proyección FIFO, no dinero (H5).
///
/// No se filtra por `nature`: los registros `capital` son ajustes del saldo y
/// cuentan como movimientos. El corte contra el saldo inicial declarado es de
/// la Fase 4, no de esta consulta.
class TransferSummaryRepositoryImpl implements TransferSummaryRepository {
  TransferSummaryRepositoryImpl(this.db);
  final AppDatabase db;

  /// Tercera rama del shape. `direction` es la columna que da el signo: `in`
  /// suma, `out` resta (H4). `amount_minor` es positivo en las tres tablas, así
  /// que el signo se aplica aparte. No trae `sale_id`, `cliente_id` ni
  /// `cliente_nombre` porque un movimiento financiero no pertenece a una venta
  /// ni a un cliente; se emiten como `NULL` para igualar el shape del UNION.
  static const String _financialEntries = '''
    UNION ALL
    SELECT f.id, f.created_event_id, f.amount_minor, f.method, f.reference,
      f.occurred_at_ms, 'financial_entry', NULL, NULL, NULL,
      e.user_id, e.device_id, e.delivery_status, e.rejection_reason,
      f.direction
    FROM financial_entries f JOIN events e ON e.event_id = f.created_event_id
    WHERE e.application_status = 'applied'
  ''';

  @override
  Stream<TransferSummary> watchTransferSummary({
    required int fromMs,
    required int toMs,
  }) {
    final query = '''
      SELECT ${MoneyMovementsSql.columns}
      FROM (
        ${MoneyMovementsSql.appliedSalesAndCustomerPayments}$_financialEntries
      )
      WHERE method = 'transfer'
        AND occurred_at_ms >= ?
        AND occurred_at_ms < ?
      ORDER BY occurred_at_ms DESC, origin, id
    ''';
    return db
        .customSelect(
          query,
          variables: [Variable<int>(fromMs), Variable<int>(toMs)],
          readsFrom: {
            db.salePayments,
            db.sales,
            db.customerPayments,
            db.clientes,
            db.financialEntries,
            db.events,
          },
        )
        .watch()
        .map(
          (rows) => TransferSummary.fromMovements(
            fromMs: fromMs,
            toMs: toMs,
            movements: rows.map(_movement).toList(),
          ),
        );
  }

  TransferMovement _movement(QueryRow row) => TransferMovement(
    id: row.read<String>('id'),
    eventId: row.read<String>('event_id'),
    origin: TransferOrigin.fromCode(row.read<String>('origin')),
    method: row.read<String>('method'),
    reference: row.readNullable<String>('reference'),
    amountMinor: row.read<int>('amount_minor'),
    occurredAtMs: row.read<int>('occurred_at_ms'),
    direction: FinancialDirection.fromCode(row.read<String>('direction')),
  );
}
