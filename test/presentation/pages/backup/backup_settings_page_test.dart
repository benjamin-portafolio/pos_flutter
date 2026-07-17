import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/backup/backup_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/config/app_config_store.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/presentation/app/app_restart_scope.dart';
import 'package:pos_flutter/presentation/pages/backup/backup_settings_page.dart';

void main() {
  late AppConfig config;
  late _FakeBackupService backupService;

  setUp(() async {
    await getIt.reset();
    config = AppConfig.initial.copyWith(setupCompleted: true);
    backupService = _FakeBackupService();

    getIt.registerSingleton<AppConfigController>(AppConfigController(config));
    getIt.registerSingleton<AppConfigStore>(_FakeAppConfigStore(config));
    getIt.registerSingleton<DatabaseStateReader>(_FakeDatabaseStateReader());
    getIt.registerSingleton<BackupService>(backupService);
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('reinicia dependencias despues de restaurar respaldo de Drive', (
    tester,
  ) async {
    var restartCount = 0;

    await tester.pumpWidget(
      AppRestartScope(
        initialConfig: config,
        restartDependencies: (previousConfig) async {
          restartCount++;
          return DependencyBootstrap(appConfig: previousConfig);
        },
        builder: (_) =>
            const MaterialApp(home: Scaffold(body: BackupSettingsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Conectar Google Drive'));
    await tester.tap(find.text('Conectar Google Drive'));
    await tester.pumpAndSettle();

    expect(backupService.restoreCount, 1);
    expect(restartCount, 1);
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

class _FakeDatabaseStateReader implements DatabaseStateReader {
  @override
  Future<DatabaseState> readState() async {
    return const DatabaseState(eventCount: 0, lastLocalSequence: 0);
  }
}

class _FakeBackupService implements BackupService {
  var restoreCount = 0;

  @override
  Future<BackupRestoreResult> restoreIfLocalDatabaseEmpty({
    bool interactiveAuth = true,
  }) async {
    restoreCount++;
    return const BackupRestoreResult(
      status: BackupRestoreStatus.restored,
      requiresRestart: true,
    );
  }

  @override
  Future<BackupRunResult> backupNow({
    bool interactiveAuth = true,
    DateTime? now,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<BackupRunResult> backupIfChanged({
    bool interactiveAuth = false,
    DateTime? now,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<InitialLocalDatabaseSetupResult> setupInitialLocalDatabase({
    required AppConfig config,
    bool interactiveAuth = true,
    DateTime? now,
  }) {
    throw UnimplementedError();
  }
}
