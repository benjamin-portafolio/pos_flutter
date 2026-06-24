import 'package:flutter/material.dart';

import '../../../application/sync/sync_endpoint_config.dart';
import '../../../application/sync/sync_push_service.dart';
import '../../../core/di/injection.dart';

class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final SyncEndpointConfig _endpointConfig;
  late final SyncPushService _syncPushService;
  late final TextEditingController _serverController;

  bool _isSyncing = false;
  bool _isTestingConnection = false;

  @override
  void initState() {
    super.initState();
    _endpointConfig = getIt<SyncEndpointConfig>();
    _syncPushService = getIt<SyncPushService>();
    _serverController = TextEditingController(text: _endpointConfig.baseUrl);
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
          Text('Sincronizacion', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
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
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _guardarServidor,
                icon: const Icon(Icons.save),
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
      ),
    );
  }

  String? _validarServidor(String? value) {
    try {
      SyncEndpointConfig.normalizeBaseUrl(value ?? '');
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  void _guardarServidor() {
    if (!_aplicarServidorActual()) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Servidor aplicado: ${_endpointConfig.baseUrl}')),
    );
  }

  Future<void> _probarConexion() async {
    if (!_aplicarServidorActual()) return;

    setState(() => _isTestingConnection = true);

    try {
      final result = await _syncPushService.testConnection();
      if (!mounted) return;

      final message = result.isSuccessful
          ? 'Conexion OK: HTTP ${result.statusCode}'
          : 'Servidor alcanzado: HTTP ${result.statusCode}';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on SyncPushException catch (error) {
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
    if (!_aplicarServidorActual()) return;

    setState(() {
      _isSyncing = true;
    });

    try {
      final report = await _syncPushService.pushPendingEvents();
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mensajeReporte(report))));
    } on SyncPushException catch (error) {
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

  bool _aplicarServidorActual() {
    if (!(_formKey.currentState?.validate() ?? false)) return false;

    setState(() {
      _endpointConfig.updateFromInput(_serverController.text);
      _serverController.text = _endpointConfig.baseUrl;
    });

    return true;
  }
}
