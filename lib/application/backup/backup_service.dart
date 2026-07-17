import 'dart:io';

import '../config/app_config.dart';
import '../config/app_config_controller.dart';
import '../config/app_config_store.dart';
import 'backup_manifest.dart';
import 'backup_store.dart';

class DatabaseState {
  const DatabaseState({
    required this.eventCount,
    required this.lastLocalSequence,
  });

  final int eventCount;
  final int lastLocalSequence;

  bool get hasLocalData => eventCount > 0;
}

class DatabaseSnapshot {
  const DatabaseSnapshot({
    required this.file,
    required this.schemaVersion,
    required this.eventCount,
    required this.lastLocalSequence,
    required this.sha256,
  });

  final File file;
  final int schemaVersion;
  final int eventCount;
  final int lastLocalSequence;
  final String sha256;
}

abstract interface class DatabaseStateReader {
  Future<DatabaseState> readState();
}

abstract interface class DatabaseSnapshotService {
  Future<DatabaseSnapshot> createSnapshot();
}

abstract interface class DatabaseRestoreService {
  Future<void> restoreSnapshot(File snapshotFile, {required String sha256});
}

enum BackupRunStatus {
  completed,
  skippedDisabled,
  skippedNoChanges,
  skippedAuthUnavailable,
}

class BackupRunResult {
  const BackupRunResult({required this.status, this.manifest, this.account});

  final BackupRunStatus status;
  final BackupManifest? manifest;
  final BackupAccount? account;

  bool get didCreateBackup => status == BackupRunStatus.completed;
}

enum BackupRestoreStatus {
  restored,
  skippedDisabled,
  skippedAuthUnavailable,
  skippedLocalDataExists,
  skippedNoRemoteBackup,
  skippedGoogleAccountMismatch,
}

class BackupRestoreResult {
  const BackupRestoreResult({
    required this.status,
    this.manifest,
    this.account,
    this.requiresRestart = false,
  });

  final BackupRestoreStatus status;
  final BackupManifest? manifest;
  final BackupAccount? account;
  final bool requiresRestart;

  bool get didRestore => status == BackupRestoreStatus.restored;
}

enum InitialLocalDatabaseSetupStatus {
  restoredFromBackup,
  createdAndBackedUp,
  skippedAuthUnavailable,
  skippedGoogleAccountMismatch,
}

class InitialLocalDatabaseSetupResult {
  const InitialLocalDatabaseSetupResult({
    required this.status,
    this.manifest,
    this.account,
    this.requiresRestart = false,
  });

  final InitialLocalDatabaseSetupStatus status;
  final BackupManifest? manifest;
  final BackupAccount? account;
  final bool requiresRestart;

  bool get didComplete =>
      status == InitialLocalDatabaseSetupStatus.restoredFromBackup ||
      status == InitialLocalDatabaseSetupStatus.createdAndBackedUp;
}

class BackupService {
  BackupService({
    required String deviceId,
    required AppConfigController appConfigController,
    required AppConfigStore appConfigStore,
    required BackupStore backupStore,
    required DatabaseStateReader stateReader,
    required DatabaseSnapshotService snapshotService,
    required DatabaseRestoreService restoreService,
  }) : _deviceId = deviceId,
       _appConfigController = appConfigController,
       _appConfigStore = appConfigStore,
       _backupStore = backupStore,
       _stateReader = stateReader,
       _snapshotService = snapshotService,
       _restoreService = restoreService;

  final String _deviceId;
  final AppConfigController _appConfigController;
  final AppConfigStore _appConfigStore;
  final BackupStore _backupStore;
  final DatabaseStateReader _stateReader;
  final DatabaseSnapshotService _snapshotService;
  final DatabaseRestoreService _restoreService;

  Future<BackupRunResult> backupNow({
    bool interactiveAuth = true,
    DateTime? now,
  }) async {
    final config = _appConfigController.config;
    if (!config.usesGoogleDriveBackup) {
      return const BackupRunResult(status: BackupRunStatus.skippedDisabled);
    }

    final session = await _backupStore.openSession(
      interactive: interactiveAuth,
    );
    if (session == null) {
      return const BackupRunResult(
        status: BackupRunStatus.skippedAuthUnavailable,
      );
    }

    final createdAt = now ?? DateTime.now();
    return _backupWithSession(session: session, config: config, now: createdAt);
  }

  Future<BackupRunResult> backupIfChanged({
    bool interactiveAuth = false,
    DateTime? now,
  }) async {
    final config = _appConfigController.config;
    if (!config.usesGoogleDriveBackup) {
      return const BackupRunResult(status: BackupRunStatus.skippedDisabled);
    }

    final state = await _stateReader.readState();
    final lastBackedUpSequence = config.lastBackupLocalSequence ?? 0;
    if (state.lastLocalSequence <= lastBackedUpSequence) {
      return const BackupRunResult(status: BackupRunStatus.skippedNoChanges);
    }

    return backupNow(interactiveAuth: interactiveAuth, now: now);
  }

  Future<BackupRestoreResult> restoreIfLocalDatabaseEmpty({
    bool interactiveAuth = true,
  }) async {
    final config = _appConfigController.config;
    if (!config.usesGoogleDriveBackup) {
      return const BackupRestoreResult(
        status: BackupRestoreStatus.skippedDisabled,
      );
    }

    final state = await _stateReader.readState();
    if (state.hasLocalData) {
      return const BackupRestoreResult(
        status: BackupRestoreStatus.skippedLocalDataExists,
      );
    }

    final session = await _backupStore.openSession(
      interactive: interactiveAuth,
    );
    if (session == null) {
      return const BackupRestoreResult(
        status: BackupRestoreStatus.skippedAuthUnavailable,
      );
    }

    await _saveGoogleAccount(config, session.account);

    final manifest = await session.readLatestManifest();
    if (manifest == null) {
      return BackupRestoreResult(
        status: BackupRestoreStatus.skippedNoRemoteBackup,
        account: session.account,
      );
    }

    if (manifest.googleUserId != session.account.userId) {
      return BackupRestoreResult(
        status: BackupRestoreStatus.skippedGoogleAccountMismatch,
        manifest: manifest,
        account: session.account,
      );
    }

    final tempDir = await Directory.systemTemp.createTemp('pos_restore_');
    try {
      final databaseFile = await session.downloadLatestDatabase(
        destination: tempDir,
      );
      if (databaseFile == null) {
        return BackupRestoreResult(
          status: BackupRestoreStatus.skippedNoRemoteBackup,
          manifest: manifest,
          account: session.account,
        );
      }

      await _restoreService.restoreSnapshot(
        databaseFile,
        sha256: manifest.sha256,
      );
      await _saveConfig(
        _appConfigController.config.copyWith(
          authProvider: 'google',
          backupProvider: BackupProvider.googleDrive,
          googleUserId: session.account.userId,
          googleUserEmail: session.account.email,
          lastBackupAt: manifest.backupCreatedAt,
          lastBackupLocalSequence: manifest.lastLocalSequence,
        ),
      );

      return BackupRestoreResult(
        status: BackupRestoreStatus.restored,
        manifest: manifest,
        account: session.account,
        requiresRestart: true,
      );
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  Future<InitialLocalDatabaseSetupResult> setupInitialLocalDatabase({
    required AppConfig config,
    bool interactiveAuth = true,
    DateTime? now,
  }) async {
    if (!config.usesGoogleDriveBackup) {
      return const InitialLocalDatabaseSetupResult(
        status: InitialLocalDatabaseSetupStatus.skippedAuthUnavailable,
      );
    }

    final session = await _backupStore.openSession(
      interactive: interactiveAuth,
    );
    if (session == null) {
      return const InitialLocalDatabaseSetupResult(
        status: InitialLocalDatabaseSetupStatus.skippedAuthUnavailable,
      );
    }

    final connectedConfig = config.copyWith(
      authProvider: 'google',
      backupProvider: BackupProvider.googleDrive,
      googleUserId: session.account.userId,
      googleUserEmail: session.account.email,
    );

    final manifest = await session.readLatestManifest();
    if (manifest == null) {
      final backup = await _backupWithSession(
        session: session,
        config: connectedConfig,
        now: now ?? DateTime.now(),
      );
      return InitialLocalDatabaseSetupResult(
        status: InitialLocalDatabaseSetupStatus.createdAndBackedUp,
        manifest: backup.manifest,
        account: session.account,
      );
    }

    if (manifest.googleUserId != session.account.userId) {
      return InitialLocalDatabaseSetupResult(
        status: InitialLocalDatabaseSetupStatus.skippedGoogleAccountMismatch,
        manifest: manifest,
        account: session.account,
      );
    }

    final tempDir = await Directory.systemTemp.createTemp(
      'pos_initial_restore_',
    );
    try {
      final databaseFile = await session.downloadLatestDatabase(
        destination: tempDir,
      );
      if (databaseFile == null) {
        throw const BackupStoreException(
          'El manifest remoto existe, pero no se encontro la base respaldada.',
        );
      }

      await _restoreService.restoreSnapshot(
        databaseFile,
        sha256: manifest.sha256,
      );
      await _saveConfig(
        connectedConfig.copyWith(
          lastBackupAt: manifest.backupCreatedAt,
          lastBackupLocalSequence: manifest.lastLocalSequence,
        ),
      );

      return InitialLocalDatabaseSetupResult(
        status: InitialLocalDatabaseSetupStatus.restoredFromBackup,
        manifest: manifest,
        account: session.account,
        requiresRestart: true,
      );
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  Future<void> _saveGoogleAccount(
    AppConfig config,
    BackupAccount account,
  ) async {
    await _saveConfig(
      config.copyWith(
        authProvider: 'google',
        backupProvider: BackupProvider.googleDrive,
        googleUserId: account.userId,
        googleUserEmail: account.email,
      ),
    );
  }

  Future<void> _saveConfig(AppConfig config) async {
    await _appConfigStore.saveConfig(config);
    _appConfigController.update(config);
  }

  Future<BackupRunResult> _backupWithSession({
    required BackupStoreSession session,
    required AppConfig config,
    required DateTime now,
  }) async {
    final snapshot = await _snapshotService.createSnapshot();

    try {
      final manifest = BackupManifest(
        mode: AppMode.standalone,
        googleUserId: session.account.userId,
        deviceId: _deviceId,
        schemaVersion: snapshot.schemaVersion,
        backupCreatedAt: now,
        eventCount: snapshot.eventCount,
        lastLocalSequence: snapshot.lastLocalSequence,
        databaseFile: BackupManifest.latestDatabaseFileName,
        sha256: snapshot.sha256,
      );

      await session.uploadBackup(
        databaseFile: snapshot.file,
        manifest: manifest,
      );
      await _saveConfig(
        config.copyWith(
          authProvider: 'google',
          backupProvider: BackupProvider.googleDrive,
          googleUserId: session.account.userId,
          googleUserEmail: session.account.email,
          lastBackupAt: now,
          lastBackupLocalSequence: snapshot.lastLocalSequence,
        ),
      );

      return BackupRunResult(
        status: BackupRunStatus.completed,
        manifest: manifest,
        account: session.account,
      );
    } finally {
      await _deleteTemporarySnapshot(snapshot.file);
    }
  }

  Future<void> _deleteTemporarySnapshot(File snapshotFile) async {
    final parent = snapshotFile.parent;
    if (await parent.exists()) {
      await parent.delete(recursive: true);
    }
  }
}
