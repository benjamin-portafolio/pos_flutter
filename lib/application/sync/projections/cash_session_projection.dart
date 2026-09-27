import 'sync_projection.dart';
import '../payloads/caja_cerrada_payload.dart';

class CashSessionProjection extends SyncProjection {
  const CashSessionProjection({
    required super.id,
    required super.active,
    required super.version,
    required super.createdEventId,
    required super.lastEventId,
    required super.lastServerSequence,
    required this.deviceId,
    required this.openedByUserId,
    required this.status,
    required this.openedAtMs,
    required this.openingMinor,
    this.closedByUserId,
    this.previousCloseEventId,
    this.close,
  });
  final String deviceId, openedByUserId, status;
  final String? closedByUserId, previousCloseEventId;
  final int openedAtMs, openingMinor;
  final CajaCerradaPayload? close;
}
