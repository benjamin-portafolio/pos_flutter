import 'dart:async';

import '../config/app_config_controller.dart';
import 'backup_service.dart';

class BackupScheduler {
  BackupScheduler({
    required AppConfigController appConfigController,
    required BackupService backupService,
  }) : _appConfigController = appConfigController,
       _backupService = backupService;

  final AppConfigController _appConfigController;
  final BackupService _backupService;

  Timer? _timer;
  bool _isRunning = false;

  void start() {
    if (_timer != null) return;

    unawaited(runDueBackup());
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(runDueBackup());
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<BackupRunResult?> runDueBackup({DateTime? now}) async {
    if (_isRunning) return null;

    final config = _appConfigController.config;
    if (!config.usesGoogleDriveBackup) return null;

    final currentTime = now ?? DateTime.now();
    final scheduledTime = DateTime(
      currentTime.year,
      currentTime.month,
      currentTime.day,
      config.backupHour,
    );
    if (currentTime.isBefore(scheduledTime)) return null;

    final lastBackupAt = config.lastBackupAt?.toLocal();
    if (lastBackupAt != null && !lastBackupAt.isBefore(scheduledTime)) {
      return null;
    }

    _isRunning = true;
    try {
      return await _backupService.backupIfChanged(
        interactiveAuth: false,
        now: currentTime,
      );
    } finally {
      _isRunning = false;
    }
  }
}
