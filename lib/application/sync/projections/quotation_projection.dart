import 'sync_projection.dart';

class QuotationProjection extends SyncProjection {
  const QuotationProjection({
    required super.id,
    required super.active,
    required super.version,
    required super.createdEventId,
    required super.lastEventId,
    required super.lastServerSequence,
    required this.userId,
    required this.deviceId,
    required this.issuedAtLocal,
    required this.sourceSaleId,
    required this.sourceDraftEventId,
    required this.currentSaleId,
  });
  final String userId, deviceId, sourceSaleId, sourceDraftEventId;
  final String? currentSaleId;
  final DateTime issuedAtLocal;
}
