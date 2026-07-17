import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/backup/backup_manifest.dart';
import 'package:pos_flutter/application/backup/backup_service.dart';
import 'package:pos_flutter/application/backup/backup_store.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/config/app_config_store.dart';

void main() {
  late AppConfigController controller;
  late _FakeAppConfigStore configStore;
  late _FakeBackupStore backupStore;
  late _FakeDatabaseStateReader stateReader;
  late _FakeDatabaseSnapshotService snapshotService;
  late _FakeDatabaseRestoreService restoreService;
  late BackupService service;

  setUp(() {
    final config = AppConfig.initial.copyWith(setupCompleted: true);
    controller = AppConfigController(config);
    configStore = _FakeAppConfigStore(config);
    backupStore = _FakeBackupStore();
    stateReader = _FakeDatabaseStateReader(
      const DatabaseState(eventCount: 2, lastLocalSequence: 2),
    );
    snapshotService = _FakeDatabaseSnapshotService();
    restoreService = _FakeDatabaseRestoreService();
    service = BackupService(
      deviceId: 'device-1',
      appConfigController: controller,
      appConfigStore: configStore,
      backupStore: backupStore,
      stateReader: stateReader,
      snapshotService: snapshotService,
      restoreService: restoreService,
    );
  });

  tearDown(() async {
    await controller.dispose();
    await snapshotService.dispose();
  });

  test('backupNow sube snapshot y persiste metadata de Google Drive', () async {
    final now = DateTime.utc(2026, 7, 9, 3);

    final result = await service.backupNow(now: now);

    expect(result.status, BackupRunStatus.completed);
    expect(backupStore.session.uploadedManifest, isNotNull);
    expect(backupStore.session.uploadedManifest!.mode, AppMode.standalone);
    expect(backupStore.session.uploadedManifest!.googleUserId, 'google-1');
    expect(backupStore.session.uploadedManifest!.deviceId, 'device-1');
    expect(backupStore.session.uploadedManifest!.eventCount, 2);
    expect(backupStore.session.uploadedManifest!.lastLocalSequence, 2);
    expect(backupStore.session.uploadedDatabaseExistsAtUpload, isTrue);

    expect(configStore.config.googleUserId, 'google-1');
    expect(configStore.config.googleUserEmail, 'user@example.com');
    expect(configStore.config.lastBackupAt, now);
    expect(configStore.config.lastBackupLocalSequence, 2);
  });

  test(
    'backupIfChanged omite respaldo si no avanzo la secuencia local',
    () async {
      final config = controller.config.copyWith(lastBackupLocalSequence: 2);
      controller.update(config);
      configStore.config = config;

      final result = await service.backupIfChanged();

      expect(result.status, BackupRunStatus.skippedNoChanges);
      expect(snapshotService.createCount, 0);
      expect(backupStore.session.uploadedManifest, isNull);
    },
  );

  test(
    'restoreIfLocalDatabaseEmpty no restaura cuando hay datos locales',
    () async {
      final result = await service.restoreIfLocalDatabaseEmpty();

      expect(result.status, BackupRestoreStatus.skippedLocalDataExists);
      expect(backupStore.openSessionCount, 0);
      expect(restoreService.restoreCount, 0);
    },
  );

  test(
    'setupInitialLocalDatabase restaura respaldo remoto antes de crear snapshot',
    () async {
      final manifest = BackupManifest(
        mode: AppMode.standalone,
        googleUserId: 'google-1',
        deviceId: 'device-remote',
        schemaVersion: 3,
        backupCreatedAt: DateTime.utc(2026, 7, 8, 3),
        eventCount: 5,
        lastLocalSequence: 9,
        databaseFile: BackupManifest.latestDatabaseFileName,
        sha256: 'remote-sha',
      );
      backupStore.session.latestManifest = manifest;

      final result = await service.setupInitialLocalDatabase(
        config: AppConfig.initial.copyWith(setupCompleted: true),
      );

      expect(result.status, InitialLocalDatabaseSetupStatus.restoredFromBackup);
      expect(result.requiresRestart, isTrue);
      expect(snapshotService.createCount, 0);
      expect(restoreService.restoreCount, 1);
      expect(restoreService.lastSha256, 'remote-sha');
      expect(backupStore.session.uploadedManifest, isNull);
      expect(configStore.config.googleUserId, 'google-1');
      expect(configStore.config.googleUserEmail, 'user@example.com');
      expect(configStore.config.lastBackupAt, manifest.backupCreatedAt);
      expect(configStore.config.lastBackupLocalSequence, 9);
    },
  );

  test(
    'setupInitialLocalDatabase crea base nueva y la respalda si Drive no tiene respaldo',
    () async {
      final now = DateTime.utc(2026, 7, 9, 4);

      final result = await service.setupInitialLocalDatabase(
        config: AppConfig.initial.copyWith(setupCompleted: true),
        now: now,
      );

      expect(result.status, InitialLocalDatabaseSetupStatus.createdAndBackedUp);
      expect(result.requiresRestart, isFalse);
      expect(snapshotService.createCount, 1);
      expect(restoreService.restoreCount, 0);
      expect(backupStore.session.uploadedManifest, isNotNull);
      expect(backupStore.session.uploadedManifest!.backupCreatedAt, now);
      expect(configStore.config.googleUserId, 'google-1');
      expect(configStore.config.googleUserEmail, 'user@example.com');
      expect(configStore.config.lastBackupAt, now);
      expect(configStore.config.lastBackupLocalSequence, 2);
    },
  );

  test('backupNow queda desactivado en serverSync', () async {
    final config = controller.config.copyWith(mode: AppMode.serverSync);
    controller.update(config);
    configStore.config = config;

    final result = await service.backupNow();

    expect(result.status, BackupRunStatus.skippedDisabled);
    expect(backupStore.openSessionCount, 0);
  });
}

class _FakeAppConfigStore implements AppConfigStore {
  _FakeAppConfigStore(this.config);

  AppConfig config;

  @override
  Future<AppConfig> readConfig() async => config;

  @override
  Future<void> saveConfig(AppConfig config) async {
    this.config = config;
  }
}

class _FakeBackupStore implements BackupStore {
  final session = _FakeBackupStoreSession();
  var openSessionCount = 0;

  @override
  Future<BackupStoreSession?> openSession({required bool interactive}) async {
    openSessionCount++;
    return session;
  }
}

class _FakeBackupStoreSession implements BackupStoreSession {
  @override
  BackupAccount get account =>
      const BackupAccount(userId: 'google-1', email: 'user@example.com');

  BackupManifest? uploadedManifest;
  BackupManifest? latestManifest;
  bool uploadedDatabaseExistsAtUpload = false;

  @override
  Future<File?> downloadLatestDatabase({required Directory destination}) async {
    await destination.create(recursive: true);
    final file = File('${destination.path}/remote.db');
    await file.writeAsBytes([4, 5, 6], flush: true);
    return file;
  }

  @override
  Future<BackupManifest?> readLatestManifest() async {
    return latestManifest;
  }

  @override
  Future<void> uploadBackup({
    required File databaseFile,
    required BackupManifest manifest,
  }) async {
    uploadedDatabaseExistsAtUpload = await databaseFile.exists();
    uploadedManifest = manifest;
  }
}

class _FakeDatabaseStateReader implements DatabaseStateReader {
  _FakeDatabaseStateReader(this.state);

  DatabaseState state;

  @override
  Future<DatabaseState> readState() async => state;
}

class _FakeDatabaseSnapshotService implements DatabaseSnapshotService {
  Directory? _tempDir;
  var createCount = 0;

  @override
  Future<DatabaseSnapshot> createSnapshot() async {
    createCount++;
    _tempDir = await Directory.systemTemp.createTemp('backup_service_test_');
    final file = File('${_tempDir!.path}/snapshot.db');
    await file.writeAsBytes([1, 2, 3], flush: true);
    return DatabaseSnapshot(
      file: file,
      schemaVersion: 3,
      eventCount: 2,
      lastLocalSequence: 2,
      sha256: 'sha',
    );
  }

  Future<void> dispose() async {
    final tempDir = _tempDir;
    if (tempDir != null && await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

class _FakeDatabaseRestoreService implements DatabaseRestoreService {
  var restoreCount = 0;
  String? lastSha256;

  @override
  Future<void> restoreSnapshot(
    File snapshotFile, {
    required String sha256,
  }) async {
    restoreCount++;
    lastSha256 = sha256;
  }
}
