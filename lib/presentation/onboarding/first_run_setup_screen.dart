import 'package:flutter/material.dart';

import '../../application/config/app_config.dart';
import '../../application/config/app_config_controller.dart';
import '../../application/config/app_config_store.dart';
import '../../application/sync/sync_availability_monitor.dart';
import '../../application/sync/sync_endpoint_config.dart';
import '../../application/sync/sync_endpoint_store.dart';
import '../../core/di/injection.dart';
import '../pages/pantalla_principal/home_screen.dart';

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
                subtitle: const Text('Pendiente de configurar en otra fase.'),
                trailing: const Chip(label: Text('Despues')),
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
                label: const Text('Guardar y entrar'),
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
      if (_mode == AppMode.serverSync) {
        final nextBaseUrl = SyncEndpointConfig.normalizeBaseUrl(
          _serverController.text,
        );
        await getIt<SyncEndpointStore>().saveBaseUrl(nextBaseUrl);
        getIt<SyncEndpointConfig>().updateFromInput(nextBaseUrl);
      }

      final config = AppConfig.initial.copyWith(
        mode: _mode,
        setupCompleted: true,
        businessName: AppConfig.defaultBusinessName,
        userId: AppConfig.defaultUserId,
        userName: AppConfig.defaultUserName,
        authProvider: 'local',
        backupProvider: 'none',
      );

      await getIt<AppConfigStore>().saveConfig(config);
      getIt<AppConfigController>().update(config);

      if (_mode == AppMode.serverSync) {
        getIt<SyncAvailabilityMonitor>().start();
      } else {
        await getIt<SyncAvailabilityMonitor>().stop();
      }

      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
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
