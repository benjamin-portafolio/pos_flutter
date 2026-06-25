import 'dart:convert';

class SyncEvent {
  const SyncEvent({
    required this.eventId,
    required this.aggregateType,
    required this.aggregateId,
    required this.eventType,
    required this.deviceId,
    required this.userId,
    required this.createdAtLocal,
    required this.payload,
    this.localSequence,
    this.serverSequence,
    this.baseServerSequence,
    this.baseVersion,
    this.createdAtServer,
    this.syncStatus = 'pending',
  });

  final String eventId;
  final String aggregateType;
  final String aggregateId;
  final String eventType;
  final String deviceId;
  final String userId;
  final int? localSequence;
  final int? serverSequence;
  final int? baseServerSequence;
  final int? baseVersion;
  final DateTime createdAtLocal;
  final DateTime? createdAtServer;
  final Map<String, Object?> payload;
  final String syncStatus;

  String get payloadJson => jsonEncode(payload);

  SyncEvent withLocalSequence(int value) {
    return SyncEvent(
      eventId: eventId,
      aggregateType: aggregateType,
      aggregateId: aggregateId,
      eventType: eventType,
      deviceId: deviceId,
      userId: userId,
      localSequence: value,
      serverSequence: serverSequence,
      baseServerSequence: baseServerSequence,
      baseVersion: baseVersion,
      createdAtLocal: createdAtLocal,
      createdAtServer: createdAtServer,
      payload: payload,
      syncStatus: syncStatus,
    );
  }

  Map<String, Object?> toPushJson() {
    return {
      'event_id': eventId,
      'aggregate_type': aggregateType,
      'aggregate_id': aggregateId,
      'event_type': eventType,
      'device_id': deviceId,
      'user_id': userId,
      'local_sequence': localSequence,
      'base_server_sequence': baseServerSequence,
      'base_version': baseVersion,
      'created_at_local': createdAtLocal.toUtc().toIso8601String(),
      'payload': payload,
    };
  }

  factory SyncEvent.fromJson(Map<String, Object?> json) {
    return SyncEvent(
      eventId: json['event_id']! as String,
      aggregateType: json['aggregate_type']! as String,
      aggregateId: json['aggregate_id']! as String,
      eventType: json['event_type']! as String,
      deviceId: json['device_id']! as String,
      userId: json['user_id']! as String,
      localSequence: json['local_sequence'] as int?,
      serverSequence: json['server_sequence'] as int?,
      baseServerSequence: json['base_server_sequence'] as int?,
      baseVersion: json['base_version'] as int?,
      createdAtLocal: DateTime.parse(json['created_at_local']! as String),
      createdAtServer: json['created_at_server'] == null
          ? null
          : DateTime.parse(json['created_at_server']! as String),
      payload: (json['payload']! as Map).cast<String, Object?>(),
      syncStatus: json['sync_status'] as String? ?? 'pending',
    );
  }
}
