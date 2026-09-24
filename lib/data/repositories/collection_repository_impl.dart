import 'package:drift/drift.dart';
import '../../domain/cobros/collection_entry.dart';
import '../../domain/repositories/collection_repository.dart';
import '../local/drift/app_database.dart';

class CollectionRepositoryImpl implements CollectionRepository {
  CollectionRepositoryImpl(this.db);
  final AppDatabase db;
  // No se une credit_allocations: repartir o aplicar un anticipo no recibe dinero.
  static const _query = """
    SELECT p.id AS id, p.created_event_id AS event_id, p.amount_minor, p.method, p.reference,
      e.created_at_local * 1000 AS occurred_at_ms, 'sale' AS origin,
      p.sale_id, s.cliente_id, c.nombre AS cliente_nombre,
      e.user_id, e.device_id, e.delivery_status, e.rejection_reason
    FROM sale_payments p JOIN sales s ON s.id = p.sale_id
    JOIN events e ON e.event_id = p.created_event_id
    LEFT JOIN clientes c ON c.id = s.cliente_id
    WHERE e.application_status = 'applied'
    UNION ALL
    SELECT p.id, p.created_event_id, p.amount_minor, p.method, p.reference,
      p.occurred_at_ms, 'customer_payment', NULL, p.cliente_id, c.nombre,
      e.user_id, e.device_id, e.delivery_status, e.rejection_reason
    FROM customer_payments p JOIN events e ON e.event_id = p.created_event_id
    JOIN clientes c ON c.id = p.cliente_id
    WHERE e.application_status = 'applied'
    ORDER BY occurred_at_ms DESC, origin, id
  """;
  @override
  Stream<List<CollectionEntry>> watchCollections() => db
      .customSelect(
        _query,
        readsFrom: {
          db.salePayments,
          db.sales,
          db.customerPayments,
          db.clientes,
          db.events,
        },
      )
      .watch()
      .map((rows) => rows.map(_entry).toList());
  CollectionEntry _entry(QueryRow row) => CollectionEntry(
    id: row.read<String>('id'),
    eventId: row.read<String>('event_id'),
    amountMinor: row.read<int>('amount_minor'),
    method: row.read<String>('method'),
    reference: row.readNullable<String>('reference'),
    date: DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('occurred_at_ms'),
      isUtc: true,
    ).toLocal(),
    origin: row.read<String>('origin'),
    saleId: row.readNullable<String>('sale_id'),
    clienteId: row.readNullable<String>('cliente_id'),
    clienteNombre: row.readNullable<String>('cliente_nombre'),
    userId: row.read<String>('user_id'),
    deviceId: row.read<String>('device_id'),
    deliveryStatus: row.read<String>('delivery_status'),
    reason: row.readNullable<String>('rejection_reason'),
  );
}
