import 'customer_account_repository_impl.dart';
import 'package:drift/drift.dart';

import '../../domain/clientes/cliente_resumen.dart';
import '../../domain/repositories/cliente_resumen_repository.dart';
import '../local/drift/app_database.dart';

/// Resúmenes de clientes agregados en una sola consulta local.
///
/// Combina la proyección de clientes con ventas confirmadas (compras y fecha
/// del último movimiento), abonos/anticipos y créditos (saldo). La consulta es
/// observada por Drift y se vuelve a ejecutar cuando cambia alguna de esas
/// tablas, manteniendo las tarjetas actualizadas sin sincronización remota.
class ClienteResumenRepositoryImpl implements ClienteResumenRepository {
  ClienteResumenRepositoryImpl(this.db);
  final AppDatabase db;

  static const _summaryQuery =
      '''
    SELECT
      c.id AS id,
      c.nombre AS nombre,
      c.telefono AS telefono,
      c.active AS active,
      COALESCE(s.compras, 0) AS compras,
      NULLIF(MAX(COALESCE(s.ultimo_movimiento_ms,0),COALESCE(p.ultimo_movimiento_ms,0),COALESCE(r.ultimo_movimiento_ms,0),COALESCE(j.ultimo_movimiento_ms,0)),0) AS ultimo_movimiento_ms,
      COALESCE(r.saldo_minor,0) AS saldo_minor
    FROM clientes c
    LEFT JOIN (
      SELECT cliente_id, COUNT(*) AS compras,
        MAX(updated_at_local) * 1000 AS ultimo_movimiento_ms
      FROM sales
      WHERE status = 'confirmada' AND active = 1 AND cliente_id IS NOT NULL
      GROUP BY cliente_id
    ) s ON s.cliente_id = c.id
    LEFT JOIN (
      SELECT cliente_id, SUM(amount_minor) AS abonos_minor,
        MAX(occurred_at_ms) AS ultimo_movimiento_ms
      FROM customer_payments
      GROUP BY cliente_id
    ) p ON p.cliente_id = c.id
    LEFT JOIN (
      SELECT cliente_id,SUM(CASE WHEN is_payment=1 THEN amount_minor ELSE -amount_minor END) AS saldo_minor,MAX(occurred_at_ms) AS ultimo_movimiento_ms
      FROM (${CustomerAccountRepositoryImpl.entriesSql})
      GROUP BY cliente_id
    ) r ON r.cliente_id = c.id
    LEFT JOIN (
      SELECT cliente_id,MAX(occurred_at_ms) AS ultimo_movimiento_ms FROM sale_adjustments GROUP BY cliente_id
    ) j ON j.cliente_id=c.id
    ORDER BY c.nombre, c.id
  ''';

  @override
  Stream<List<ClienteResumen>> watchResumen() => db
      .customSelect(
        _summaryQuery,
        readsFrom: {
          db.clientes,
          db.sales,
          db.customerPayments,
          db.creditSales,
          db.saleAdjustments,
          db.saleCreditReductions,
          db.saleReconciliationEffects,
          db.events,
        },
      )
      .watch()
      .map((rows) => rows.map(_row).toList());

  ClienteResumen _row(QueryRow row) {
    final ultimoMovimientoMs = row.readNullable<int>('ultimo_movimiento_ms');
    return ClienteResumen(
      id: row.read<String>('id'),
      nombre: row.read<String>('nombre'),
      telefono: row.readNullable<String>('telefono'),
      active: row.read<bool>('active'),
      compras: row.read<int>('compras'),
      ultimoMovimiento: ultimoMovimientoMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              ultimoMovimientoMs,
              isUtc: true,
            ).toLocal(),
      saldoMinor: BigInt.from(row.read<int>('saldo_minor')),
    );
  }
}
