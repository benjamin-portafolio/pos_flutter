import '../../../domain/ventas/sale_status.dart';
import 'sync_projection.dart';

class SaleProjection extends SyncProjection {
  const SaleProjection({
    required super.id,
    required super.active,
    required super.version,
    required super.createdEventId,
    required super.lastEventId,
    required super.lastServerSequence,
    required this.userId,
    required this.deviceId,
    required this.status,
    required this.totalMinor,
    required this.createdAtLocal,
    required this.updatedAtLocal,
  });
  final String userId;
  final String deviceId;
  final SaleStatus status;
  final int totalMinor;
  final DateTime createdAtLocal;
  final DateTime updatedAtLocal;
}
