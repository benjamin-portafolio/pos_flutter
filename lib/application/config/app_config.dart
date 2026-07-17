enum AppMode {
  standalone,
  serverSync;

  String get storageValue {
    return switch (this) {
      AppMode.standalone => 'standalone',
      AppMode.serverSync => 'server_sync',
    };
  }

  String get label {
    return switch (this) {
      AppMode.standalone => 'Local',
      AppMode.serverSync => 'Servidor',
    };
  }

  static AppMode fromStorage(Object? value) {
    return switch (value) {
      'server_sync' => AppMode.serverSync,
      _ => AppMode.standalone,
    };
  }
}

enum BackupProvider {
  none,
  googleDrive;

  String get storageValue {
    return switch (this) {
      BackupProvider.none => 'none',
      BackupProvider.googleDrive => 'google_drive',
    };
  }

  String get label {
    return switch (this) {
      BackupProvider.none => 'Sin respaldo',
      BackupProvider.googleDrive => 'Google Drive',
    };
  }

  static BackupProvider fromStorage(Object? value) {
    return switch (value) {
      'google_drive' => BackupProvider.googleDrive,
      _ => BackupProvider.none,
    };
  }
}

class AppConfig {
  const AppConfig({
    required this.mode,
    required this.setupCompleted,
    required this.businessName,
    required this.userId,
    required this.userName,
    required this.authProvider,
    required this.syncProvider,
    required this.backupProvider,
    required this.backupHour,
    this.googleUserId,
    this.googleUserEmail,
    this.lastBackupAt,
    this.lastBackupLocalSequence,
  });

  static const defaultBusinessName = 'CERVECERIA MAESTRA Y Taproom';
  static const defaultUserId = 'user_active';
  static const defaultUserName = 'Benjamin Alvarado';
  static const defaultBackupHour = 3;

  static const initial = AppConfig(
    mode: AppMode.standalone,
    setupCompleted: false,
    businessName: defaultBusinessName,
    userId: defaultUserId,
    userName: defaultUserName,
    authProvider: 'google',
    syncProvider: 'none',
    backupProvider: BackupProvider.googleDrive,
    backupHour: defaultBackupHour,
  );

  final AppMode mode;
  final bool setupCompleted;
  final String businessName;
  final String userId;
  final String userName;
  final String authProvider;
  final String syncProvider;
  final BackupProvider backupProvider;
  final String? googleUserId;
  final String? googleUserEmail;
  final int backupHour;
  final DateTime? lastBackupAt;
  final int? lastBackupLocalSequence;

  bool get isStandalone => mode == AppMode.standalone;

  bool get isServerSync => mode == AppMode.serverSync;

  bool get usesGoogleDriveBackup =>
      isStandalone && backupProvider == BackupProvider.googleDrive;

  static String defaultAuthProviderForMode(AppMode mode) {
    return switch (mode) {
      AppMode.standalone => 'google',
      AppMode.serverSync => 'backend_jwt',
    };
  }

  static String defaultSyncProviderForMode(AppMode mode) {
    return switch (mode) {
      AppMode.standalone => 'none',
      AppMode.serverSync => 'pos_server',
    };
  }

  static BackupProvider defaultBackupProviderForMode(AppMode mode) {
    return switch (mode) {
      AppMode.standalone => BackupProvider.googleDrive,
      AppMode.serverSync => BackupProvider.none,
    };
  }

  AppConfig copyWith({
    AppMode? mode,
    bool? setupCompleted,
    String? businessName,
    String? userId,
    String? userName,
    String? authProvider,
    String? syncProvider,
    BackupProvider? backupProvider,
    Object? googleUserId = _sentinel,
    Object? googleUserEmail = _sentinel,
    int? backupHour,
    Object? lastBackupAt = _sentinel,
    Object? lastBackupLocalSequence = _sentinel,
  }) {
    final nextMode = mode ?? this.mode;
    final modeChanged = mode != null && mode != this.mode;
    final nextBackupProvider =
        backupProvider ??
        (modeChanged
            ? defaultBackupProviderForMode(nextMode)
            : this.backupProvider);
    final clearsGoogleIdentity =
        nextMode == AppMode.serverSync ||
        nextBackupProvider != BackupProvider.googleDrive;

    return AppConfig(
      mode: nextMode,
      setupCompleted: setupCompleted ?? this.setupCompleted,
      businessName: businessName ?? this.businessName,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      authProvider:
          authProvider ??
          (modeChanged
              ? defaultAuthProviderForMode(nextMode)
              : this.authProvider),
      syncProvider:
          syncProvider ??
          (modeChanged
              ? defaultSyncProviderForMode(nextMode)
              : this.syncProvider),
      backupProvider: nextBackupProvider,
      googleUserId: clearsGoogleIdentity
          ? null
          : _valueOrCurrent<String?>(googleUserId, this.googleUserId),
      googleUserEmail: clearsGoogleIdentity
          ? null
          : _valueOrCurrent<String?>(googleUserEmail, this.googleUserEmail),
      backupHour: backupHour ?? this.backupHour,
      lastBackupAt: clearsGoogleIdentity
          ? null
          : _valueOrCurrent<DateTime?>(lastBackupAt, this.lastBackupAt),
      lastBackupLocalSequence: clearsGoogleIdentity
          ? null
          : _valueOrCurrent<int?>(
              lastBackupLocalSequence,
              this.lastBackupLocalSequence,
            ),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'mode': mode.storageValue,
      'setup_completed': setupCompleted,
      'business_name': businessName,
      'user_id': userId,
      'user_name': userName,
      'auth_provider': authProvider,
      'sync_provider': syncProvider,
      'backup_provider': backupProvider.storageValue,
      'google_user_id': googleUserId,
      'google_user_email': googleUserEmail,
      'backup_hour': backupHour,
      'last_backup_at': lastBackupAt?.toUtc().toIso8601String(),
      'last_backup_local_sequence': lastBackupLocalSequence,
    };
  }

  factory AppConfig.fromJson(Map<String, Object?> json) {
    final mode = AppMode.fromStorage(json['mode']);
    final storedBackupProvider = BackupProvider.fromStorage(
      json['backup_provider'],
    );
    final backupProvider =
        storedBackupProvider == BackupProvider.none &&
            mode == AppMode.standalone
        ? BackupProvider.googleDrive
        : AppConfig.defaultBackupProviderForMode(mode);
    final backupHour =
        _readInt(json['backup_hour']) ?? AppConfig.defaultBackupHour;
    final storedAuthProvider = json['auth_provider'] as String?;

    return AppConfig(
      mode: mode,
      setupCompleted: json['setup_completed'] == true,
      businessName:
          json['business_name'] as String? ?? AppConfig.defaultBusinessName,
      userId: json['user_id'] as String? ?? AppConfig.defaultUserId,
      userName: json['user_name'] as String? ?? AppConfig.defaultUserName,
      authProvider: storedAuthProvider == null || storedAuthProvider == 'local'
          ? AppConfig.defaultAuthProviderForMode(mode)
          : storedAuthProvider,
      syncProvider:
          json['sync_provider'] as String? ??
          AppConfig.defaultSyncProviderForMode(mode),
      backupProvider: backupProvider,
      googleUserId: json['google_user_id'] as String?,
      googleUserEmail: json['google_user_email'] as String?,
      backupHour: backupHour.clamp(0, 23).toInt(),
      lastBackupAt: _readDateTime(json['last_backup_at']),
      lastBackupLocalSequence: _readInt(json['last_backup_local_sequence']),
    );
  }

  static const _sentinel = Object();

  static T _valueOrCurrent<T>(Object? value, T current) {
    if (identical(value, _sentinel)) return current;
    return value as T;
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _readDateTime(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }
}
