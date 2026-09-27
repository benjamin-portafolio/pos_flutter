import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';

void main() {
  test('initial standalone usa Google Drive como respaldo conceptual', () {
    expect(AppConfig.initial.mode, AppMode.standalone);
    expect(AppConfig.initial.authProvider, 'google');
    expect(AppConfig.initial.syncProvider, 'none');
    expect(AppConfig.initial.backupProvider, BackupProvider.googleDrive);
    expect(AppConfig.initial.usesGoogleDriveBackup, isTrue);
  });

  test('cambiar a serverSync desactiva respaldo Google y limpia cuenta', () {
    final config = AppConfig.initial.copyWith(
      setupCompleted: true,
      googleUserId: 'google-user',
      googleUserEmail: 'user@example.com',
      lastBackupAt: DateTime(2026),
      lastBackupLocalSequence: 12,
    );

    final serverConfig = config.copyWith(mode: AppMode.serverSync);

    expect(serverConfig.authProvider, 'backend_jwt');
    expect(serverConfig.syncProvider, 'pos_server');
    expect(serverConfig.backupProvider, BackupProvider.none);
    expect(serverConfig.googleUserId, isNull);
    expect(serverConfig.googleUserEmail, isNull);
    expect(serverConfig.lastBackupAt, isNull);
    expect(serverConfig.lastBackupLocalSequence, isNull);
  });

  test('serializa y lee metadatos de respaldo', () {
    final config = AppConfig.initial.copyWith(
      setupCompleted: true,
      googleUserId: 'google-user',
      googleUserEmail: 'user@example.com',
      backupHour: 22,
      lastBackupAt: DateTime.utc(2026, 7, 9, 3),
      lastBackupLocalSequence: 8,
    );

    final decoded = AppConfig.fromJson(config.toJson());

    expect(decoded.backupProvider, BackupProvider.googleDrive);
    expect(decoded.googleUserId, 'google-user');
    expect(decoded.googleUserEmail, 'user@example.com');
    expect(decoded.backupHour, 22);
    expect(decoded.lastBackupAt, DateTime.utc(2026, 7, 9, 3));
    expect(decoded.lastBackupLocalSequence, 8);
  });

  test('normaliza config viejo local a proveedores del modo standalone', () {
    final decoded = AppConfig.fromJson(const {
      'mode': 'standalone',
      'setup_completed': true,
      'auth_provider': 'local',
      'sync_provider': 'none',
      'backup_provider': 'none',
    });

    expect(decoded.authProvider, 'google');
    expect(decoded.syncProvider, 'none');
    expect(decoded.backupProvider, BackupProvider.googleDrive);
  });

  test('la captura de caja esta habilitada por defecto', () {
    expect(AppConfig.initial.cashEnabled, isTrue);
  });

  test('serializa y lee la captura de caja', () {
    final decoded = AppConfig.fromJson(
      AppConfig.initial.copyWith(cashEnabled: false).toJson(),
    );

    expect(decoded.cashEnabled, isFalse);
  });

  test('una instalacion sin la clave conserva la captura habilitada', () {
    final decoded = AppConfig.fromJson(const {
      'mode': 'standalone',
      'setup_completed': true,
      'auth_provider': 'google',
      'sync_provider': 'none',
      'backup_provider': 'google_drive',
    });

    expect(decoded.cashEnabled, isTrue);
  });

  test('copyWith conserva la captura de caja al no indicarla', () {
    final disabled = AppConfig.initial.copyWith(cashEnabled: false);

    expect(disabled.copyWith(setupCompleted: true).cashEnabled, isFalse);
    expect(disabled.copyWith(cashEnabled: true).cashEnabled, isTrue);
  });
}
