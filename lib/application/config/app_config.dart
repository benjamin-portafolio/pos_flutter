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
  });

  static const defaultBusinessName = 'CERVECERIA MAESTRA Y Taproom';
  static const defaultUserId = 'user_active';
  static const defaultUserName = 'Benjamin Alvarado';

  static const initial = AppConfig(
    mode: AppMode.standalone,
    setupCompleted: false,
    businessName: defaultBusinessName,
    userId: defaultUserId,
    userName: defaultUserName,
    authProvider: 'local',
    syncProvider: 'none',
    backupProvider: 'none',
  );

  final AppMode mode;
  final bool setupCompleted;
  final String businessName;
  final String userId;
  final String userName;
  final String authProvider;
  final String syncProvider;
  final String backupProvider;

  bool get isStandalone => mode == AppMode.standalone;

  bool get isServerSync => mode == AppMode.serverSync;

  AppConfig copyWith({
    AppMode? mode,
    bool? setupCompleted,
    String? businessName,
    String? userId,
    String? userName,
    String? authProvider,
    String? syncProvider,
    String? backupProvider,
  }) {
    final nextMode = mode ?? this.mode;
    return AppConfig(
      mode: nextMode,
      setupCompleted: setupCompleted ?? this.setupCompleted,
      businessName: businessName ?? this.businessName,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      authProvider: authProvider ?? this.authProvider,
      syncProvider:
          syncProvider ??
          (nextMode == AppMode.serverSync ? 'pos_server' : 'none'),
      backupProvider: backupProvider ?? this.backupProvider,
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
      'backup_provider': backupProvider,
    };
  }

  factory AppConfig.fromJson(Map<String, Object?> json) {
    final mode = AppMode.fromStorage(json['mode']);
    return AppConfig(
      mode: mode,
      setupCompleted: json['setup_completed'] == true,
      businessName:
          json['business_name'] as String? ?? AppConfig.defaultBusinessName,
      userId: json['user_id'] as String? ?? AppConfig.defaultUserId,
      userName: json['user_name'] as String? ?? AppConfig.defaultUserName,
      authProvider: json['auth_provider'] as String? ?? 'local',
      syncProvider:
          json['sync_provider'] as String? ??
          (mode == AppMode.serverSync ? 'pos_server' : 'none'),
      backupProvider: json['backup_provider'] as String? ?? 'none',
    );
  }
}
