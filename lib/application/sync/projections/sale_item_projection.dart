import '../payloads/sale_item_snapshot.dart';
import 'sync_projection.dart';

class SaleItemProjection extends SyncProjection {
  const SaleItemProjection({
    required super.id,
    required super.active,
    required super.version,
    required super.createdEventId,
    required super.lastEventId,
    required super.lastServerSequence,
    required this.saleId,
    required this.sortOrder,
    required this.snapshot,
  });
  final String saleId;
  final int sortOrder;
  final SaleItemSnapshot snapshot;
}
