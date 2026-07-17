import 'package:flutter/material.dart';

import '../../../application/backup/backup_service.dart';
import '../../../application/config/app_config.dart';
import '../../../application/config/app_config_controller.dart';
import '../../../application/config/app_config_store.dart';
import '../../../core/di/injection.dart';
import '../../app/app_restart_scope.dart';

class BackupSettingsPage extends StatelessWidget {
  const BackupSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Respaldo')),
      body: const BackupSettingsScreen(),
    );
  }
}

class BackupSettingsScreen extends StatefulWidget {
  const BackupSettingsScreen({super.key});

  @override
  State<BackupSettingsScreen> createState() => _BackupSettingsScreenState();
}

class _BackupSettingsScreenState extends State<BackupSettingsScreen> {
  late final AppConfigController _appConfigController;
  late final AppConfigStore _appConfigStore;
  late final BackupService _backupService;
  late final DatabaseStateReader _databaseStateReader;

  bool _isConnecting = false;
  bool _isBackingUp = false;
  bool _isSavingHour = false;
  DatabaseState? _databaseState;

  @override
  void initState() {
    super.initState();
    _appConfigController = getIt<AppConfigController>();
    _appConfigStore = getIt<AppConfigStore>();
    _backupService = getIt<BackupService>();
    _databaseStateReader = getIt<DatabaseStateReader>();
    _loadDatabaseState();
  }

  @override
  Widget build(BuildContext context) {
    final config = _appConfigController.config;
    final enabled = config.usesGoogleDriveBackup;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Google Drive', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(enabled ? Icons.cloud_done : Icons.cloud_off),
            title: Text(enabled ? 'Respaldo activo' : 'Respaldo desactivado'),
            subtitle: Text(
              enabled
                  ? (config.googleUserEmail ?? 'Cuenta Google pendiente')
                  : 'Modo servidor',
            ),
            trailing: Chip(label: Text(config.backupProvider.label)),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: config.backupHour,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Hora de respaldo',
              prefixIcon: Icon(Icons.schedule),
            ),
            items: List.generate(
              24,
              (hour) => DropdownMenuItem(
                value: hour,
                child: Text('${hour.toString().padLeft(2, '0')}:00'),
              ),
            ),
            onChanged: enabled && !_isSavingHour ? _saveBackupHour : null,
          ),
          const SizedBox(height: 16),
          _BackupStatus(config: config, state: _databaseState),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: enabled && !_isConnecting ? _connectAndRestore : null,
            icon: _isConnecting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.account_circle),
            label: const Text('Conectar Google Drive'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: enabled && !_isBackingUp ? _backupNow : null,
            icon: _isBackingUp
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload),
            label: const Text('Respaldar ahora'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadDatabaseState() async {
    try {
      final state = await _databaseStateReader.readState();
      if (!mounted) return;
      setState(() => _databaseState = state);
    } catch (_) {
      if (!mounted) return;
      setState(() => _databaseState = null);
    }
  }

  Future<void> _saveBackupHour(int? value) async {
    if (value == null) return;

    setState(() => _isSavingHour = true);
    try {
      final config = _appConfigController.config.copyWith(backupHour: value);
      await _appConfigStore.saveConfig(config);
      _appConfigController.update(config);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar la hora.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingHour = false);
      }
    }
  }

  Future<void> _connectAndRestore() async {
    setState(() => _isConnecting = true);

    try {
      final result = await _backupService.restoreIfLocalDatabaseEmpty(
        interactiveAuth: true,
      );
      if (result.requiresRestart) {
        if (!mounted) return;
        await AppRestartScope.restart(context);
        return;
      }

      await _loadDatabaseState();
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_restoreMessage(result))));
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo conectar Google Drive.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  Future<void> _backupNow() async {
    setState(() => _isBackingUp = true);

    try {
      final result = await _backupService.backupNow(interactiveAuth: true);
      await _loadDatabaseState();
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_backupMessage(result))));
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo crear el respaldo.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isBackingUp = false);
      }
    }
  }

  String _backupMessage(BackupRunResult result) {
    return switch (result.status) {
      BackupRunStatus.completed =>
        'Respaldo completo: secuencia ${result.manifest?.lastLocalSequence ?? 0}.',
      BackupRunStatus.skippedDisabled => 'Respaldo desactivado.',
      BackupRunStatus.skippedNoChanges => 'No hay cambios nuevos.',
      BackupRunStatus.skippedAuthUnavailable =>
        'No se pudo autorizar Google Drive.',
    };
  }

  String _restoreMessage(BackupRestoreResult result) {
    return switch (result.status) {
      BackupRestoreStatus.restored => 'Respaldo restaurado.',
      BackupRestoreStatus.skippedDisabled => 'Respaldo desactivado.',
      BackupRestoreStatus.skippedAuthUnavailable =>
        'No se pudo autorizar Google Drive.',
      BackupRestoreStatus.skippedLocalDataExists =>
        'Cuenta conectada. Hay datos locales, no se restauro automatico.',
      BackupRestoreStatus.skippedNoRemoteBackup =>
        'Cuenta conectada. No hay respaldo remoto todavia.',
      BackupRestoreStatus.skippedGoogleAccountMismatch =>
        'El respaldo remoto pertenece a otra cuenta Google.',
    };
  }
}

class _BackupStatus extends StatelessWidget {
  const _BackupStatus({required this.config, required this.state});

  final AppConfig config;
  final DatabaseState? state;

  @override
  Widget build(BuildContext context) {
    final lastBackupAt = config.lastBackupAt?.toLocal();
    final lastBackupText = lastBackupAt == null
        ? 'Sin respaldo'
        : '${lastBackupAt.year}-${lastBackupAt.month.toString().padLeft(2, '0')}-'
              '${lastBackupAt.day.toString().padLeft(2, '0')} '
              '${lastBackupAt.hour.toString().padLeft(2, '0')}:'
              '${lastBackupAt.minute.toString().padLeft(2, '0')}';

    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.history),
          title: const Text('Ultimo respaldo'),
          subtitle: Text(lastBackupText),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.storage),
          title: const Text('Datos locales'),
          subtitle: Text(
            state == null
                ? 'No disponible'
                : '${state!.eventCount} eventos, secuencia ${state!.lastLocalSequence}',
          ),
        ),
      ],
    );
  }
}
