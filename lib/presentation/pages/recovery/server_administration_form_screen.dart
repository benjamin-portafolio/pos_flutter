import 'package:flutter/material.dart';
import '../../../application/config/app_config.dart';
import '../../../application/config/app_config_controller.dart';
import '../../../application/recovery/recovery_admin_client.dart';
import '../../../application/sync/sync_endpoint_config.dart';
import '../../../core/di/injection.dart';
import 'server_administration_access.dart';

class ServerAdministrationFormScreen extends StatefulWidget {
  const ServerAdministrationFormScreen({
    super.key,
    this.client,
    this.mode,
    this.initialDestination,
    this.enrollment = false,
  });
  final RecoveryAdminClient? client;
  final AppMode? mode;
  final String? initialDestination;
  final bool enrollment;
  @override
  State<ServerAdministrationFormScreen> createState() =>
      _ServerAdministrationFormScreenState();
}

class _ServerAdministrationFormScreenState
    extends State<ServerAdministrationFormScreen> {
  late final RecoveryAdminClient _client =
      widget.client ?? getIt<RecoveryAdminClient>();
  late final AppMode _mode = widget.mode ?? getIt<AppConfigController>().mode;
  late final TextEditingController _destination = TextEditingController(
    text: widget.initialDestination ?? getIt<SyncEndpointConfig>().baseUrl,
  );
  final _credential = TextEditingController();
  final _destinationFocus = FocusNode(debugLabel: 'Servidor de administración');
  final _credentialFocus = FocusNode(debugLabel: 'Contraseña administrativa');
  bool _obscureCredential = true;
  Map<String, Object?>? _snapshot;
  bool _busy = false;
  String? _error;
  String? _message;

  @override
  void dispose() {
    _client.cancel();
    _destinationFocus.dispose();
    _credentialFocus.dispose();
    _destination.dispose();
    _credential.clear();
    _credential.dispose();
    super.dispose();
  }

  void _invalidate(String _) => setState(() {
    _snapshot = null;
    _error = null;
    _message = null;
  });

  Future<void> _refresh() async {
    if (_busy || !canAdministerServer(_mode)) return;
    setState(() {
      _busy = true;
      _snapshot = null;
      _error = null;
      _message = null;
    });
    try {
      final s = await _client.inspect(
        mode: _mode,
        destination: _destination.text.trim(),
        credential: _credential.text,
      );
      if (mounted) setState(() => _snapshot = s);
    } catch (e) {
      if (mounted) setState(() => _error = _describe(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _describe(Object e) => e is FormatException
      ? e.message
      : 'No se completó la operación. Consulta el estado antes de repetirla.';

  Future<void> _execute(String action, {Map? request}) async {
    final snapshot = _snapshot;
    if (_busy || snapshot == null || !canAdministerServer(_mode)) return;
    final label = switch (action) {
      'enrollment-enable' => 'Habilitar alta de dispositivos',
      'enrollment-disable' => 'Deshabilitar alta de dispositivos',
      'enable' => 'Habilitar recuperación',
      'disable' => 'Deshabilitar recuperación',
      'approve' => 'Aprobar dispositivo',
      _ => 'Rechazar solicitud',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: SingleChildScrollView(
          child: Text(
            'Servidor: ${_destination.text.trim()}\nIdentidad: ${snapshot['server_instance_id']}\nGeneración: ${snapshot['generation_id']}'
            '${request == null ? '' : "\nDispositivo: ${request['source_device_id']}\nPaquete: ${request['package_id']}\nManifest SHA-256: ${request['manifest_digest']}"}\n\n'
            '${action == 'enrollment-enable'
                ? 'Se permitirá que instalaciones vacías descarguen los datos y se vinculen a este servidor.'
                : action == 'enrollment-disable'
                ? 'Se impedirán nuevas altas. Los dispositivos ya vinculados continuarán sincronizando.'
                : action == 'approve'
                ? 'Compara estos datos con los del dispositivo de origen. Aprobar autoriza el envío de este paquete; la publicación se confirma en el dispositivo.'
                : action == 'disable'
                ? 'Se revocarán las autorizaciones pendientes. Una recuperación ya iniciada debe finalizarse o abortarse desde su dispositivo de origen.'
                : action == 'enable'
                ? 'Se permitirá solicitar recuperación sobre este destino vacío. Los datos se enviarán desde el dispositivo elegido.'
                : 'El dispositivo ya no podrá continuar con esta solicitud.'}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(label),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !identical(_snapshot, snapshot)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
      _snapshot = null;
    });
    try {
      await _client.execute(
        mode: _mode,
        destination: _destination.text.trim(),
        credential: _credential.text,
        snapshot: snapshot,
        action: action,
        requestId: request?['request_id'] as String?,
      );
      final updated = await _client.inspect(
        mode: _mode,
        destination: _destination.text.trim(),
        credential: _credential.text,
      );
      if (mounted) {
        setState(() {
          _snapshot = updated;
          _message = 'Acción registrada. Estado actualizado.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _describe(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!canAdministerServer(_mode)) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            widget.enrollment
                ? 'Alta de dispositivos'
                : 'Recuperación del servidor',
          ),
        ),
        body: const Center(
          child: Text('Disponible en computadora y en modo servidor.'),
        ),
      );
    }
    final snapshot = _snapshot;
    final eligibility = snapshot?['eligibility'] as Map?;
    final enabled = snapshot?['recovery_enabled'] == true;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.enrollment
              ? 'Alta de dispositivos'
              : 'Recuperación del servidor',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                widget.enrollment
                    ? 'Alta de dispositivos'
                    : 'Preparar recuperación del servidor',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                widget.enrollment
                    ? 'Permite vincular instalaciones vacías y descargar los datos del servidor recuperado.'
                    : 'Autoriza un dispositivo para reconstruir un servidor vacío. El origen prepara, envía y confirma la publicación de sus datos desde Configuración → Recuperar servidor desde este dispositivo.',
              ),
              const SizedBox(height: 8),
              Text(
                widget.enrollment
                    ? 'Los dispositivos que ya tienen datos o una vinculación anterior requieren una revisión antes de reemplazar su base. Deshabilitar el alta no desconecta a los equipos vinculados.'
                    : 'Se recupera el corte conservado por ese dispositivo; puede faltar información que solo existía en otros equipos. Este proceso no reemplaza los datos de un servidor en uso.',
              ),
              const SizedBox(height: 24),
              TextField(
                key: const ValueKey('server_admin_destination'),
                controller: _destination,
                focusNode: _destinationFocus,
                readOnly: _busy,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _credentialFocus.requestFocus(),
                onChanged: _invalidate,
                decoration: const InputDecoration(
                  labelText: 'URL del servidor de destino',
                  border: OutlineInputBorder(),
                  helperText:
                      'Cambiar este destino no cambia el servidor de sincronización de la app.',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('server_admin_password'),
                controller: _credential,
                focusNode: _credentialFocus,
                // Keep the native editable control while a request is running.
                // Disabling/re-enabling it can lose the desktop input responder.
                readOnly: _busy,
                obscureText: _obscureCredential,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _refresh(),
                enableSuggestions: false,
                autocorrect: false,
                onChanged: _invalidate,
                decoration: InputDecoration(
                  labelText: 'Contraseña administrativa',
                  suffixIcon: IconButton(
                    tooltip: _obscureCredential
                        ? 'Mostrar contraseña'
                        : 'Ocultar contraseña',
                    onPressed: _busy
                        ? null
                        : () {
                            setState(
                              () => _obscureCredential = !_obscureCredential,
                            );
                            _credentialFocus.requestFocus();
                          },
                    icon: Icon(
                      _obscureCredential
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                  border: OutlineInputBorder(),
                  helperText:
                      'Usa la contraseña establecida en la consola del servidor o tu credencial anterior. No se guarda en esta app.',
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Consultar estado'),
                  ),
                  if (snapshot != null && !widget.enrollment)
                    OutlinedButton(
                      onPressed:
                          _busy ||
                              snapshot['active_recovery_id'] != null ||
                              snapshot['server_mode'] == 'recovering' ||
                              (!enabled && eligibility?['eligible'] != true)
                          ? null
                          : () => _execute(enabled ? 'disable' : 'enable'),
                      child: Text(
                        enabled
                            ? 'Deshabilitar recuperación'
                            : 'Habilitar recuperación',
                      ),
                    ),
                ],
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: LinearProgressIndicator(),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_message!),
                ),
              if (snapshot != null && widget.enrollment) ...[
                const SizedBox(height: 24),
                Text('Servidor: ${_destination.text.trim()}'),
                Text('Estado: ${_state(snapshot['server_mode'])}'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    snapshot['automatic_enrollment'] == true
                        ? 'Alta habilitada'
                        : 'Alta deshabilitada',
                  ),
                  subtitle: const Text('Permitir conectar otros dispositivos'),
                  value: snapshot['automatic_enrollment'] == true,
                  onChanged:
                      _busy ||
                          snapshot['automatic_enrollment'] is! bool ||
                          snapshot['active_recovery_id'] != null ||
                          snapshot['server_mode'] == 'recovering' ||
                          (snapshot['automatic_enrollment'] != true &&
                              (snapshot['server_mode'] != 'active' ||
                                  snapshot['dataset_id'] == null))
                      ? null
                      : (value) => _execute(
                          value ? 'enrollment-enable' : 'enrollment-disable',
                        ),
                ),
                if (snapshot['automatic_enrollment'] is! bool)
                  const Text(
                    'Actualiza el servidor para administrar el alta de dispositivos.',
                  ),
                if (snapshot['server_mode'] != 'active' ||
                    snapshot['dataset_id'] == null)
                  const Text(
                    'Primero debe completarse y publicarse la recuperación del servidor.',
                  ),
                const SizedBox(height: 16),
                const Text(
                  'En cada equipo vacío: usa modo servidor, abre Configuración → Sincronización, escribe esta URL y pulsa Aplicar para descargar la base inicial.',
                ),
              ],
              if (snapshot != null && !widget.enrollment) ...[
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Destino verificado',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        SelectableText(
                          'Identidad: ${snapshot['server_instance_id']}\nGeneración: ${snapshot['generation_id']}\nEstado: ${_state(snapshot['server_mode'])}\nRecuperación: ${enabled ? 'habilitada' : 'deshabilitada'}',
                        ),
                        if (snapshot['dataset_id'] != null)
                          SelectableText(
                            'Datos publicados: ${snapshot['dataset_id']}',
                          ),
                        if (snapshot['active_recovery_id'] != null)
                          SelectableText(
                            'Recuperación en curso: ${snapshot['active_recovery_id']}',
                          ),
                        const SizedBox(height: 8),
                        Text(
                          eligibility?['eligible'] == true
                              ? 'Destino apto para iniciar una recuperación.'
                              : 'No se puede iniciar otra recuperación en el estado actual.',
                        ),
                        for (final reason
                            in (eligibility?['reasons'] as List? ?? []))
                          Text('• ${_reason(reason)}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Solicitudes de dispositivos',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Text(
                  'Actualiza el estado después de solicitar conexión desde el origen. Se muestran las 100 solicitudes más recientes de esta generación. Verifica dispositivo, paquete y huella antes de aprobar.',
                ),
                if ((snapshot['requests'] as List).isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No hay solicitudes en esta generación.'),
                  ),
                for (final request
                    in (snapshot['requests'] as List).whereType<Map>())
                  _requestCard(request, snapshot),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _requestCard(Map r, Map<String, Object?> snapshot) {
    final canDecide =
        !_busy &&
        snapshot['active_recovery_id'] == null &&
        snapshot['server_mode'] != 'recovering' &&
        (r['session_state'] == null || r['session_state'] == 'aborted');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dispositivo: ${r['source_device_id']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SelectableText(
              'Solicitud: ${r['request_id']}\nPaquete: ${r['package_id']}\nManifest SHA-256: ${r['manifest_digest']}',
            ),
            Text(
              'Decisión: ${_state(r['decision'])} · Sesión: ${_state(r['session_state'])} · Lotes recibidos: ${r['received_chunks'] ?? 0}',
            ),
            Text('Solicitada: ${r['created_at']}'),
            if (r['diagnostic'] != null)
              ExpansionTile(
                title: const Text('Diagnóstico de validación'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(r['diagnostic'].toString()),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: [
                FilledButton(
                  onPressed:
                      canDecide &&
                          r['decision'] == 'pending' &&
                          snapshot['recovery_enabled'] == true &&
                          (snapshot['eligibility'] as Map)['eligible'] == true
                      ? () => _execute('approve', request: r)
                      : null,
                  child: const Text('Aprobar dispositivo'),
                ),
                OutlinedButton(
                  onPressed: canDecide && r['decision'] != 'rejected'
                      ? () => _execute('reject', request: r)
                      : null,
                  child: const Text('Rechazar solicitud'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _state(Object? value) =>
      const {
        'empty': 'Vacío',
        'active': 'Activo',
        'recovering': 'En recuperación',
        'pending': 'Pendiente',
        'approved': 'Aprobada',
        'rejected': 'Rechazada',
        'receiving': 'Recibiendo',
        'validating': 'Validando',
        'failed_validation': 'Validación fallida',
        'ready_to_commit': 'Lista para publicar',
        'completed': 'Completada',
        'aborted': 'Abortada',
      }[value] ??
      (value?.toString() ?? 'Sin iniciar');
  String _reason(Object? value) =>
      const {
        'destination_not_empty':
            'El destino ya contiene datos o vinculaciones.',
        'incompatible_schema': 'El esquema del servidor es incompatible.',
        'active_recovery': 'Hay una recuperación en curso.',
        'unpublished_staging': 'Hay datos de una recuperación sin publicar.',
      }[value] ??
      value.toString();
}
