import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:workmanager_android/workmanager_android.dart';
import 'package:workmanager_platform_interface/workmanager_platform_interface.dart';

import '../../application/backup/backup_scheduler.dart';
import '../../application/config/app_config_controller.dart';
import 'application_dependencies.dart';
import 'data_dependencies.dart';

const _backupWorkUniqueName = 'pos_google_drive_backup_periodic';
const _backupWorkTaskName = 'pos_google_drive_backup_due';
const _backupWorkTag = 'pos_google_drive_backup';

final _workmanager = WorkmanagerAndroid();
var _workmanagerInitialized = false;
_AndroidBackgroundTaskHandler? _backgroundTaskHandler;

typedef _AndroidBackgroundTaskHandler =
    Future<bool> Function(String taskName, Map<String, dynamic>? inputData);

Future<void> scheduleAndroidBackupBackgroundWork() async {
  if (!Platform.isAndroid) return;

  await _ensureWorkmanagerInitialized();
  await _workmanager.registerPeriodicTask(
    _backupWorkUniqueName,
    _backupWorkTaskName,
    frequency: const Duration(hours: 1),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 15),
    tag: _backupWorkTag,
  );
}

Future<void> cancelAndroidBackupBackgroundWork() async {
  if (!Platform.isAndroid) return;

  await _ensureWorkmanagerInitialized();
  await _workmanager.cancelByUniqueName(_backupWorkUniqueName);
}

Future<void> _ensureWorkmanagerInitialized() async {
  if (_workmanagerInitialized) return;

  await _workmanager.initialize(androidBackupWorkCallbackDispatcher);
  _workmanagerInitialized = true;
}

@pragma('vm:entry-point')
void androidBackupWorkCallbackDispatcher() {
  _executeAndroidBackgroundTask((taskName, inputData) async {
    if (taskName != _backupWorkTaskName) return true;

    return _runAndroidBackupBackgroundTask();
  });
}

void _executeAndroidBackgroundTask(_AndroidBackgroundTaskHandler handler) {
  WidgetsFlutterBinding.ensureInitialized();

  _backgroundTaskHandler = handler;
  final flutterApi = _AndroidBackupWorkmanagerFlutterApi();
  WorkmanagerFlutterApi.setUp(flutterApi);
  flutterApi.backgroundChannelInitialized();
}

Future<bool> _runAndroidBackupBackgroundTask() async {
  WidgetsFlutterBinding.ensureInitialized();

  final taskGetIt = GetIt.asNewInstance();
  try {
    final bootstrap = await registerDataDependencies(taskGetIt);
    registerApplicationDependencies(
      taskGetIt,
      deviceId: bootstrap.deviceId,
      appConfig: bootstrap.appConfig,
      storedSyncBaseUrl: bootstrap.storedSyncBaseUrl,
      requireWifiForServerDetection: bootstrap.requireWifiForServerDetection,
    );

    final config = taskGetIt<AppConfigController>().config;
    if (!config.setupCompleted || !config.usesGoogleDriveBackup) return true;

    await taskGetIt<BackupScheduler>().runDueBackup();
    return true;
  } catch (_) {
    return false;
  } finally {
    await taskGetIt.reset(dispose: false);
  }
}

class _AndroidBackupWorkmanagerFlutterApi extends WorkmanagerFlutterApi {
  @override
  Future<void> backgroundChannelInitialized() async {}

  @override
  Future<bool> executeTask(
    String taskName,
    Map<String?, Object?>? inputData,
  ) async {
    final handler = _backgroundTaskHandler;
    if (handler == null) return false;

    return handler(taskName, _convertInputData(inputData));
  }

  Map<String, dynamic>? _convertInputData(Map<String?, Object?>? inputData) {
    if (inputData == null) return null;

    final converted = <String, dynamic>{};
    for (final entry in inputData.entries) {
      final key = entry.key;
      if (key != null) {
        converted[key] = entry.value;
      }
    }
    return converted;
  }
}
