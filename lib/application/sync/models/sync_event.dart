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
    String? applicationStatus,
    String? deliveryStatus,
    String? syncStatus,
    this.rejectionReason,
  }) : applicationStatus = applicationStatus ?? 'applied',
       deliveryStatus = deliveryStatus ?? syncStatus ?? 'pending';

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
  final String applicationStatus;
  final String deliveryStatus;
  final String? rejectionReason;

  String get payloadJson => jsonEncode(payload);

  String get syncStatus => deliveryStatus;

  SyncEvent withLocalSequence(int value) {
    return copyWith(localSequence: value);
  }

  SyncEvent copyWith({
    String? eventId,
    String? aggregateType,
    String? aggregateId,
    String? eventType,
    String? deviceId,
    String? userId,
    int? localSequence,
    int? serverSequence,
    int? baseServerSequence,
    int? baseVersion,
    DateTime? createdAtLocal,
    DateTime? createdAtServer,
    Map<String, Object?>? payload,
    String? applicationStatus,
    String? deliveryStatus,
    String? rejectionReason,
  }) {
    return SyncEvent(
      eventId: eventId ?? this.eventId,
      aggregateType: aggregateType ?? this.aggregateType,
      aggregateId: aggregateId ?? this.aggregateId,
      eventType: eventType ?? this.eventType,
      deviceId: deviceId ?? this.deviceId,
      userId: userId ?? this.userId,
      localSequence: localSequence ?? this.localSequence,
      serverSequence: serverSequence ?? this.serverSequence,
      baseServerSequence: baseServerSequence ?? this.baseServerSequence,
      baseVersion: baseVersion ?? this.baseVersion,
      createdAtLocal: createdAtLocal ?? this.createdAtLocal,
      createdAtServer: createdAtServer ?? this.createdAtServer,
      payload: payload ?? this.payload,
      applicationStatus: applicationStatus ?? this.applicationStatus,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      rejectionReason: rejectionReason ?? this.rejectionReason,
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
      localSequence: _readInt(json['local_sequence']),
      serverSequence: _readInt(json['server_sequence']),
      baseServerSequence: _readInt(json['base_server_sequence']),
      baseVersion: _readInt(json['base_version']),
      createdAtLocal: DateTime.parse(json['created_at_local']! as String),
      createdAtServer: json['created_at_server'] == null
          ? null
          : DateTime.parse(json['created_at_server']! as String),
      payload: _readPayload(json['payload']),
      applicationStatus: json['application_status'] as String? ?? 'applied',
      deliveryStatus:
          json['delivery_status'] as String? ??
          _deliveryStatusFromLegacySyncStatus(json['sync_status']),
      rejectionReason: json['rejection_reason'] as String?,
    );
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static Map<String, Object?> _readPayload(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, Object?>{};
  }

  static String _deliveryStatusFromLegacySyncStatus(Object? value) {
    if (value is! String) return 'pending';
    final normalized = value.toLowerCase();
    return normalized == 'synced' ? 'delivered' : normalized;
  }
}
