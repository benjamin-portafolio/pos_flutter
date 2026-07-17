import 'package:flutter/material.dart';

import '../../application/backup/backup_service.dart';
import '../../application/config/app_config.dart';
import '../../application/config/app_config_controller.dart';
import '../../application/config/app_config_store.dart';
import '../../application/sync/sync_endpoint_config.dart';
import '../../application/sync/sync_endpoint_store.dart';
import '../../core/di/injection.dart';
import '../app/app_restart_scope.dart';

class FirstRunSetupScreen extends StatefulWidget {
  const FirstRunSetupScreen({super.key});

  @override
  State<FirstRunSetupScreen> createState() => _FirstRunSetupScreenState();
}

class _FirstRunSetupScreenState extends State<FirstRunSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _serverController;
  AppMode _mode = AppMode.standalone;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final endpointConfig = getIt<SyncEndpointConfig>();
    _serverController = TextEditingController(text: endpointConfig.baseUrl);
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuracion inicial')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Modo de operacion',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AppMode>(
                initialValue: _mode,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Modo',
                  prefixIcon: Icon(Icons.settings_applications),
                ),
                items: AppMode.values
                    .map(
                      (mode) => DropdownMenuItem(
                        value: mode,
                        child: Text(mode.label),
                      ),
                    )
                    .toList(),
                onChanged: _isSaving
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _mode = value);
                      },
              ),
              const SizedBox(height: 12),
              _ModeDescription(mode: _mode),
              const SizedBox(height: 20),
              Text(
                'Datos iniciales',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: AppConfig.defaultBusinessName,
                enabled: false,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Negocio',
                  prefixIcon: Icon(Icons.store),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: AppConfig.defaultUserName,
                enabled: false,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Usuario local',
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              if (_mode == AppMode.serverSync) ...[
                const SizedBox(height: 20),
                Text(
                  'Servidor',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _serverController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '192.168.1.10:3000',
                    labelText: 'IP o URL del servidor',
                    prefixIcon: Icon(Icons.dns),
                  ),
                  keyboardType: TextInputType.url,
                  validator: _validarServidor,
                ),
              ],
              const SizedBox(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cloud_upload_outlined),
                title: const Text('Respaldo en Google Drive'),
                subtitle: Text(
                  _mode == AppMode.standalone
                      ? 'Requerido para buscar o crear el respaldo inicial.'
                      : 'Desactivado en modo servidor.',
                ),
                trailing: Chip(
                  label: Text(
                    _mode == AppMode.standalone ? 'Requerido' : 'Desactivado',
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _isSaving ? null : _guardarConfiguracion,
                icon: _isSaving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(
                  _mode == AppMode.standalone
                      ? 'Conectar Drive y entrar'
                      : 'Guardar y entrar',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _validarServidor(String? value) {
    if (_mode != AppMode.serverSync) return null;

    try {
      SyncEndpointConfig.normalizeBaseUrl(value ?? '');
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  Future<void> _guardarConfiguracion() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);

    try {
      final config = AppConfig.initial.copyWith(
        mode: _mode,
        setupCompleted: true,
        businessName: AppConfig.defaultBusinessName,
        userId: AppConfig.defaultUserId,
        userName: AppConfig.defaultUserName,
        authProvider: AppConfig.defaultAuthProviderForMode(_mode),
        syncProvider: AppConfig.defaultSyncProviderForMode(_mode),
        backupProvider: AppConfig.defaultBackupProviderForMode(_mode),
      );

      if (_mode == AppMode.serverSync) {
        final nextBaseUrl = SyncEndpointConfig.normalizeBaseUrl(
          _serverController.text,
        );
        await getIt<SyncEndpointStore>().saveBaseUrl(nextBaseUrl);
        getIt<SyncEndpointConfig>().updateFromInput(nextBaseUrl);

        await getIt<AppConfigStore>().saveConfig(config);
        getIt<AppConfigController>().update(config);
      } else {
        final result = await getIt<BackupService>().setupInitialLocalDatabase(
          config: config,
          interactiveAuth: true,
        );
        if (!result.didComplete) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(_initialSetupMessage(result))));
          return;
        }
      }

      if (!mounted) return;
      await AppRestartScope.restart(context);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar la configuracion.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String _initialSetupMessage(InitialLocalDatabaseSetupResult result) {
    return switch (result.status) {
      InitialLocalDatabaseSetupStatus.restoredFromBackup =>
        'Respaldo restaurado.',
      InitialLocalDatabaseSetupStatus.createdAndBackedUp =>
        'Base local creada y respaldada.',
      InitialLocalDatabaseSetupStatus.skippedAuthUnavailable =>
        'Debes conectar Google Drive para usar modo local.',
      InitialLocalDatabaseSetupStatus.skippedGoogleAccountMismatch =>
        'El respaldo remoto pertenece a otra cuenta Google.',
    };
  }
}

class _ModeDescription extends StatelessWidget {
  const _ModeDescription({required this.mode});

  final AppMode mode;

  @override
  Widget build(BuildContext context) {
    final text = switch (mode) {
      AppMode.standalone =>
        'SQLite local sera la fuente principal. No se inicia servidor, '
            'push, pull ni WebSocket.',
      AppMode.serverSync =>
        'La app seguira escribiendo primero en SQLite y despues intentara '
            'entregar eventos al servidor configurado.',
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              mode == AppMode.standalone ? Icons.tablet_mac : Icons.cloud_sync,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
