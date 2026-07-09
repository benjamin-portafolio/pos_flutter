import 'package:flutter/material.dart';

import '../../../application/config/app_config.dart';
import '../../../application/config/app_config_controller.dart';
import '../../../application/config/app_config_store.dart';
import '../../../application/sync/sync_availability_monitor.dart';
import '../../../application/sync/sync_detection_settings_store.dart';
import '../../../application/sync/sync_endpoint_config.dart';
import '../../../application/sync/sync_endpoint_store.dart';
import '../../../application/sync/exceptions/sync_health_exception.dart';
import '../../../application/sync/exceptions/sync_preflight_exception.dart';
import '../../../application/sync/exceptions/sync_pull_exception.dart';
import '../../../application/sync/exceptions/sync_push_exception.dart';
import '../../../application/sync/models/sync_push_report.dart';
import '../../../application/sync/sync_orchestrator.dart';
import '../../../application/sync/sync_server_detection_config.dart';
import '../../../core/di/injection.dart';

class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final AppConfigController _appConfigController;
  late final AppConfigStore _appConfigStore;
  late final SyncEndpointConfig _endpointConfig;
  late final SyncEndpointStore _endpointStore;
  late final SyncDetectionSettingsStore _detectionSettingsStore;
  late final SyncServerDetectionConfig _serverDetectionConfig;
  late final SyncAvailabilityMonitor _availabilityMonitor;
  late final SyncOrchestrator _syncOrchestrator;
  late final TextEditingController _serverController;

  bool _isSyncing = false;
  bool _isTestingConnection = false;
  bool _isSavingConfig = false;
  bool _isSavingWifiDetection = false;
  bool _requireWifiForServerDetection = false;
  late AppMode _mode;

  @override
  void initState() {
    super.initState();
    _appConfigController = getIt<AppConfigController>();
    _appConfigStore = getIt<AppConfigStore>();
    _endpointConfig = getIt<SyncEndpointConfig>();
    _endpointStore = getIt<SyncEndpointStore>();
    _detectionSettingsStore = getIt<SyncDetectionSettingsStore>();
    _serverDetectionConfig = getIt<SyncServerDetectionConfig>();
    _availabilityMonitor = getIt<SyncAvailabilityMonitor>();
    _syncOrchestrator = getIt<SyncOrchestrator>();
    _serverController = TextEditingController(text: _endpointConfig.baseUrl);
    _requireWifiForServerDetection =
        _serverDetectionConfig.requireWifiForServerDetection;
    _mode = _appConfigController.mode;
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Configuracion', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          DropdownButtonFormField<AppMode>(
            initialValue: _mode,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Modo de operacion',
              prefixIcon: Icon(Icons.settings_applications),
            ),
            items: AppMode.values
                .map(
                  (mode) =>
                      DropdownMenuItem(value: mode, child: Text(mode.label)),
                )
                .toList(),
            onChanged: _isSavingConfig
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => _mode = value);
                  },
          ),
          const SizedBox(height: 12),
          _ModeSummary(mode: _mode),
          const SizedBox(height: 20),
          Text('Datos locales', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _appConfigController.config.businessName,
            enabled: false,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Negocio',
              prefixIcon: Icon(Icons.store),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _appConfigController.config.userName,
            enabled: false,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Usuario local',
              prefixIcon: Icon(Icons.person),
            ),
          ),
          const SizedBox(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Respaldo en Google Drive'),
            subtitle: const Text('Pendiente de configurar en otra fase.'),
            trailing: const Chip(label: Text('Despues')),
          ),
          const SizedBox(height: 16),
          if (_mode == AppMode.standalone) ...[
            FilledButton.icon(
              onPressed: _isSavingConfig ? null : _guardarModoActual,
              icon: _isSavingConfig
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: const Text('Guardar configuracion local'),
            ),
          ] else ...[
            Text(
              'Sincronizacion',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Form(
              key: _formKey,
              child: TextFormField(
                controller: _serverController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '192.168.1.10:3000',
                  labelText: 'IP o URL del servidor',
                  prefixIcon: Icon(Icons.dns),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                validator: _validarServidor,
                onFieldSubmitted: (_) => _guardarServidor(),
              ),
            ),
            const SizedBox(height: 12),
            Text('URL actual: ${_endpointConfig.baseUrl}'),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.wifi),
              title: const Text('Detectar servidor solo con WiFi'),
              value: _requireWifiForServerDetection,
              onChanged: _isSavingWifiDetection
                  ? null
                  : _actualizarDeteccionPorWifi,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _isSavingConfig ? null : _guardarServidor,
                  icon: _isSavingConfig
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Aplicar'),
                ),
                OutlinedButton.icon(
                  onPressed: _isTestingConnection ? null : _probarConexion,
                  icon: _isTestingConnection
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: const Text('Probar conexion'),
                ),
                OutlinedButton.icon(
                  onPressed: _isSyncing ? null : _sincronizarPendientes,
                  icon: _isSyncing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: const Text('Enviar pendientes'),
                ),
              ],
            ),
          ],
        ],
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

  Future<void> _guardarModoActual() async {
    if (!await _guardarConfiguracionActual()) return;
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Modo aplicado: ${_mode.label}')));
  }

  Future<void> _guardarServidor() async {
    if (!await _guardarConfiguracionActual()) return;
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Servidor aplicado: ${_endpointConfig.baseUrl}')),
    );
  }

  Future<void> _probarConexion() async {
    if (!await _aplicarServidorActual()) return;

    setState(() => _isTestingConnection = true);

    try {
      final result = await _syncOrchestrator.testConnection();
      if (!mounted) return;

      if (result.isAvailable) {
        _availabilityMonitor.markServerAvailable(
          latestServerSequence: result.latestServerSequence,
        );
      }

      final message = result.isAvailable
          ? 'Conexion OK: server_sequence ${result.latestServerSequence ?? 0}'
          : 'Servidor alcanzado, health invalido: ${result.failureMessage}';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on SyncHealthException catch (error) {
      _availabilityMonitor.markServerUnavailable(error.message);
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() => _isTestingConnection = false);
      }
    }
  }

  Future<void> _sincronizarPendientes() async {
    if (!await _aplicarServidorActual()) return;

    setState(() {
      _isSyncing = true;
    });

    try {
      final report = await _syncOrchestrator.pushPendingEvents();
      if (report.total > 0) {
        _availabilityMonitor.markServerAvailable();
      }
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mensajeReporte(report))));
    } on SyncPushException catch (error) {
      _availabilityMonitor.markServerUnavailable(error.message);
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on SyncPreflightException catch (error) {
      _availabilityMonitor.markServerUnavailable(error.message);
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on SyncPullException catch (error) {
      _availabilityMonitor.markServerUnavailable(error.message);
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  String _mensajeReporte(SyncPushReport report) {
    if (report.total == 0) return 'No hay eventos pendientes.';

    final partes = <String>['${report.synced} sincronizados'];
    if (report.conflicts > 0) {
      partes.add('${report.conflicts} con conflicto');
    }
    if (report.rejected > 0) {
      partes.add('${report.rejected} rechazados');
    }
    if (report.pending > 0) {
      partes.add('${report.pending} pendientes');
    }

    return partes.join(', ');
  }

  Future<void> _actualizarDeteccionPorWifi(bool value) async {
    final previousValue = _requireWifiForServerDetection;
    setState(() {
      _requireWifiForServerDetection = value;
      _isSavingWifiDetection = true;
    });

    try {
      await _detectionSettingsStore.saveRequireWifiForServerDetection(value);
      _serverDetectionConfig.updateRequireWifiForServerDetection(value);
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _requireWifiForServerDetection = previousValue;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar la preferencia de WiFi.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingWifiDetection = false;
        });
      }
    }
  }

  Future<bool> _guardarConfiguracionActual() async {
    setState(() => _isSavingConfig = true);

    try {
      if (_mode == AppMode.serverSync && !await _aplicarServidorActual()) {
        return false;
      }

      final config = _appConfigController.config.copyWith(
        mode: _mode,
        setupCompleted: true,
        businessName: AppConfig.defaultBusinessName,
        userId: AppConfig.defaultUserId,
        userName: AppConfig.defaultUserName,
        authProvider: 'local',
        backupProvider: 'none',
      );

      await _appConfigStore.saveConfig(config);
      _appConfigController.update(config);

      if (_mode == AppMode.serverSync) {
        _availabilityMonitor.start();
        _availabilityMonitor.requestServerCheck();
      } else {
        await _availabilityMonitor.stop();
      }

      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo guardar la configuracion.')),
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _isSavingConfig = false);
      }
    }
  }

  Future<bool> _aplicarServidorActual() async {
    if (_mode != AppMode.serverSync) return true;
    if (!(_formKey.currentState?.validate() ?? false)) return false;

    final nextBaseUrl = SyncEndpointConfig.normalizeBaseUrl(
      _serverController.text,
    );
    final previousBaseUrl = _endpointConfig.baseUrl;

    try {
      await _endpointStore.saveBaseUrl(nextBaseUrl);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo guardar el servidor.')),
        );
      }
      return false;
    }

    if (!mounted) return false;

    setState(() {
      _endpointConfig.updateFromInput(nextBaseUrl);
      _serverController.text = _endpointConfig.baseUrl;
    });

    if (_endpointConfig.baseUrl != previousBaseUrl) {
      _syncOrchestrator.stopRealtimeListener();
    }

    if (_appConfigController.mode == AppMode.serverSync) {
      _availabilityMonitor.requestServerCheck();
    }
    return true;
  }
}

class _ModeSummary extends StatelessWidget {
  const _ModeSummary({required this.mode});

  final AppMode mode;

  @override
  Widget build(BuildContext context) {
    final icon = mode == AppMode.standalone
        ? Icons.tablet_mac
        : Icons.cloud_sync;
    final text = switch (mode) {
      AppMode.standalone =>
        'Modo local: SQLite es la fuente principal y no se intenta conectar '
            'con servidor.',
      AppMode.serverSync =>
        'Modo servidor: la app escribe localmente y luego entrega eventos '
            'por preflight, push y pull.',
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
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
