import '../config/app_config.dart';

class BackupManifest {
  const BackupManifest({
    required this.mode,
    required this.googleUserId,
    required this.deviceId,
    required this.schemaVersion,
    required this.backupCreatedAt,
    required this.eventCount,
    required this.lastLocalSequence,
    required this.databaseFile,
    required this.sha256,
  });

  static const latestDatabaseFileName = 'pos_backup_latest.db';
  static const manifestFileName = 'pos_backup_manifest.json';

  final AppMode mode;
  final String googleUserId;
  final String deviceId;
  final int schemaVersion;
  final DateTime backupCreatedAt;
  final int eventCount;
  final int lastLocalSequence;
  final String databaseFile;
  final String sha256;

  Map<String, Object?> toJson() {
    return {
      'mode': mode.storageValue,
      'googleUserId': googleUserId,
      'deviceId': deviceId,
      'schemaVersion': schemaVersion,
      'backupCreatedAt': backupCreatedAt.toUtc().toIso8601String(),
      'eventCount': eventCount,
      'lastLocalSequence': lastLocalSequence,
      'databaseFile': databaseFile,
      'sha256': sha256,
    };
  }

  factory BackupManifest.fromJson(Map<String, Object?> json) {
    return BackupManifest(
      mode: AppMode.fromStorage(json['mode']),
      googleUserId: json['googleUserId'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      schemaVersion: _readInt(json['schemaVersion']) ?? 0,
      backupCreatedAt:
          DateTime.tryParse(json['backupCreatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      eventCount: _readInt(json['eventCount']) ?? 0,
      lastLocalSequence: _readInt(json['lastLocalSequence']) ?? 0,
      databaseFile:
          json['databaseFile'] as String? ??
          BackupManifest.latestDatabaseFileName,
      sha256: json['sha256'] as String? ?? '',
    );
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
