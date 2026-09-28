import 'package:drift/drift.dart';
import '../../domain/cobros/collection_entry.dart';
import '../../domain/repositories/collection_repository.dart';
import '../local/drift/app_database.dart';
import '../local/drift/money_movements_sql.dart';

class CollectionRepositoryImpl implements CollectionRepository {
  CollectionRepositoryImpl(this.db);
  final AppDatabase db;
  // La forma normalizada vive en MoneyMovementsSql para que el agregado de
  // transferencias la extienda en vez de duplicarla (R5). La columna `direction`
  // se agregó para eso y este informe no la lee.
  static const _query =
      '${MoneyMovementsSql.appliedSalesAndCustomerPayments}'
      'ORDER BY occurred_at_ms DESC, origin, id';
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
