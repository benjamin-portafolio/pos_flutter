import 'dart:convert';
import '../../app/app_restart_scope.dart';
import 'package:flutter/material.dart';
import '../../../application/config/app_config.dart';
import '../../../application/recovery/recovery_cancellation.dart';
import '../../../application/recovery/recovery_destination_inspector.dart';
import '../../../application/recovery/recovery_readiness_service.dart';

/// Acceso de preparación: no presenta publicación/vinculación como disponibles
/// mientras sus dependencias S4 y la sustitución coordinada no estén completas.
class RecoveryReadinessScreen extends StatefulWidget {
  const RecoveryReadinessScreen({
    required this.mode,
    required this.service,
    required this.inspector,
    super.key,
  });
  final AppMode mode;
  final RecoveryReadinessService service;
  final RecoveryDestinationInspector inspector;

  @override
  State<RecoveryReadinessScreen> createState() =>
      _RecoveryReadinessScreenState();
}

class _RecoveryReadinessScreenState extends State<RecoveryReadinessScreen> {
  final _destination = TextEditingController();
  final _token = TextEditingController();
  final _enrollment = TextEditingController();
  bool _confirmBinding = false;
  bool _binding = false;
  final _cancellation = RecoveryCancellation();
  Map<String, Object?>? _source;
  Map<String, Object?>? _target;
  Map<String, Object?>? _package;
  Map<String, Object?>? _attempt;
  List<Map<String, Object?>> _history = [];
  bool _confirmPublication = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final attempt = await widget.service.attempt(),
          package = await widget.service.prepared();
      final history = await widget.service.history();
      if (mounted) {
        setState(() {
          _attempt = attempt;
          _package = package;
          _history = history;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo leer el intento conservado.');
      }
    }
  }

  String? _error;
  String? _checkedDestination;
  bool _busy = false;

  @override
  void dispose() {
    _cancellation.cancel();
    widget.inspector.cancel();
    _destination.dispose();
    _token.clear();
    _token.dispose();
    _enrollment.clear();
    _enrollment.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message.toString());
    } on RecoveryCancelled {
      // Salir cancela trabajo local pendiente; no hay sesión remota que abortar.
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo completar la comprobación. Los datos de origen se conservan.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _diagnose() => _run(() async {
    setState(() => _source = null);
    final report = await widget.service.diagnose(widget.mode, _cancellation);
    if (mounted) setState(() => _source = report);
  });

  Future<void> _prepare() => _run(() async {
    final source = _source;
    if (source == null) return;
    final package = await widget.service.preparePackage(
      source,
      widget.mode,
      _cancellation,
    );
    if (mounted) setState(() => _package = package);
  });
  Future<void> _transfer({bool publish = false, bool abort = false}) =>
      _run(() async {
        if (_attempt == null) {
          final target = _target,
              package = _package,
              destination = _checkedDestination;
          if (target == null || package == null || destination == null) {
            throw const FormatException(
              'Prepara el paquete y comprueba el destino.',
            );
          }
          final attempt = await widget.service.beginTransfer(
            package,
            target,
            destination,
            _token.text.trim(),
            widget.mode,
          );
          if (mounted) setState(() => _attempt = attempt);
          _token.clear();
        }
        final attempt = await widget.service.transfer(
          _cancellation,
          publish: publish,
          abort: abort,
          onProgress: (value) {
            if (mounted) setState(() => _attempt = value);
          },
        );
        if (mounted) {
          setState(() {
            _attempt = attempt;
            _confirmPublication = false;
          });
        }
      });

  Future<void> _archive() => _run(() async {
    await widget.service.archiveAttempt();
    if (mounted) {
      setState(() {
        _attempt = null;
        _package = null;
        _source = null;
        _target = null;
      });
    }
    await _restore();
  });
  Future<void> _reopen(String key) => _run(() async {
    await widget.service.reopenAttempt(key);
    await _restore();
  });

  Future<void> _bind() => _run(() async {
    setState(() => _binding = true);
    try {
      await widget.service.bindSource(_enrollment.text.trim());
    } finally {
      if (mounted) setState(() => _binding = false);
    }
    _enrollment.clear();
    if (mounted) await AppRestartScope.restart(context);
  });

  Future<void> _inspect() => _run(() async {
    setState(() {
      _target = null;
      _checkedDestination = null;
    });
    final input = _destination.text.trim();
    final uri = Uri.tryParse(input);
    if (uri == null) throw const FormatException('Ingresa una URL completa.');
    final report = await widget.inspector.inspect(
      mode: widget.mode,
      destination: uri,
      token: _token.text.trim(),
    );
    if (mounted) {
      setState(() {
        _target = report;
        _checkedDestination = input;
      });
    }
  });

  @override
  Widget build(BuildContext context) {
    final source = _package ?? _source;
    // El manifiesto toma su identidad de origen de este mismo corte.
    final packageCut = _package?['cut'] as Map?;
    final packageSource = packageCut?['source'] as Map?;
    final sourceDeviceId = packageSource?['device_id'];
    final diagnostic = source?['diagnostic'] as Map?;
    final cut = source?['cut'] as Map?;
    final target = _target;
    return PopScope(
      canPop: !_binding,
      child: Scaffold(
        appBar: AppBar(title: const Text('Recuperar servidor')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Recuperar servidor desde este dispositivo',
              style: TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 12),
            const Text(
              'Revisa el corte y el destino antes de publicar. Puedes salir y '
              'reanudar el mismo intento; el origen y sus cambios se conservan.',
            ),
            const SizedBox(height: 12),
            Text(
              widget.mode == AppMode.standalone
                  ? 'Modo local: solo diagnóstico local. No se contactará ningún servidor.'
                  : 'La sincronización habitual permanece pausada mientras esta pantalla está abierta.',
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy || _package != null || _attempt != null
                  ? null
                  : _diagnose,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Diagnosticar origen'),
            ),
            if (source != null) ...[
              const SizedBox(height: 12),
              Text('Fecha del corte: ${cut?['cut_at']}'),
              Text('Captura conservada en: ${source['snapshot_path']}'),
              Text(
                diagnostic?['admissible'] == true
                    ? 'Origen admisible para preparar un paquete. No acredita aceptación del destino.'
                    : 'Origen bloqueado: ${diagnostic?['blocking_count']} comprobaciones no satisfechas.',
              ),
              for (final issue
                  in (diagnostic?['blockers'] as List? ?? const []))
                Text('• ${_reason((issue as Map)['code'].toString())}'),
              for (final warning
                  in (diagnostic?['warnings'] as List? ?? const []))
                Text('Advertencia: ${_reason(warning.toString())}'),
              const Text(
                'Se excluyen borradores, cotizaciones, preferencias y diarios locales. '
                'Los datos SQLite excluidos se conservan en la captura; las preferencias '
                'externas permanecen en la instalación. No se garantiza recuperar '
                'operaciones que nunca llegaron a este dispositivo.',
              ),
              ExpansionTile(
                title: const Text('Alcance disponible en el corte'),
                children: [
                  for (final entry
                      in (diagnostic?['counts'] as Map? ?? const {}).entries)
                    ListTile(
                      dense: true,
                      title: Text(entry.key.toString()),
                      trailing: Text('${entry.value}'),
                    ),
                ],
              ),
            ],
            if (widget.mode == AppMode.serverSync &&
                diagnostic?['admissible'] == true &&
                _package == null)
              OutlinedButton(
                onPressed: _busy ? null : _prepare,
                child: const Text('Preparar paquete del corte'),
              ),
            if (_package != null) ...[
              Text('Paquete: ${_package!['package_id']}'),
              SelectableText('Digest: ${_package!['manifest_digest']}'),
              if (sourceDeviceId is String && sourceDeviceId.isNotEmpty)
                SelectableText('ID del dispositivo de origen: $sourceDeviceId'),
              Text('Conservado en: ${_package!['package_path']}'),
              const Text(
                'Entrega el ID del paquete, el digest y el ID del dispositivo de origen '
                'al operador para obtener la credencial temporal.',
              ),
            ],
            if (widget.mode == AppMode.serverSync) ...[
              const SizedBox(height: 20),
              const Text('Servidor destino'),
              TextField(
                controller: _destination,
                enabled: !_busy,
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {
                  _target = null;
                  _checkedDestination = null;
                }),
                decoration: const InputDecoration(
                  labelText: 'URL HTTPS del destino',
                ),
              ),
              TextField(
                controller: _token,
                enabled: !_busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() {
                  _target = null;
                  _checkedDestination = null;
                }),
                decoration: const InputDecoration(
                  labelText: 'Credencial temporal del operador',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy ? null : _inspect,
                child: const Text('Comprobar destino'),
              ),
              if (target != null) ...[
                Text('Destino comprobado: $_checkedDestination'),
                Text('Identidad: ${target['server_instance_id']}'),
                Text('Generación: ${target['generation_id']}'),
                Text(
                  target['eligible'] == true
                      ? 'Elegible en esta consulta; aún no está reservado.'
                      : 'Destino bloqueado.',
                ),
                for (final reason in (target['reasons'] as List))
                  Text('• ${_reason(reason.toString())}'),
                if (target['commercial_recovery_complete'] != true)
                  const Text(
                    'El destino no admite todavía recuperar todo el negocio: ventas, caja e inventario.',
                  ),
                const Text(
                  'La secuencia 0 no demuestra que un servidor esté vacío. '
                  'Esta comprobación no modifica el endpoint habitual ni inicia una recuperación.',
                ),
              ],
            ],
            if (widget.mode == AppMode.serverSync &&
                _attempt == null &&
                _package != null &&
                _target?['eligible'] == true &&
                _target?['commercial_recovery_complete'] == true)
              FilledButton(
                onPressed: _busy ? null : () => _transfer(),
                child: const Text('Transferir y validar paquete'),
              ),
            if (_attempt != null) ...[
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await widget.service.renewCredential(
                          _token.text.trim(),
                        );
                        _token.clear();
                      }),
                child: const Text(
                  'Actualizar credencial temporal de este intento',
                ),
              ),
              Text('Destino del intento: ${_attempt!['destination']}'),
              Text('Generación del intento: ${_attempt!['generation_id']}'),
              Text('Estado: ${_attempt!['state']}'),
              Text(
                'Lotes confirmados: ${_attempt!['received_chunks'] ?? 0} / ${_attempt!['total_chunks'] ?? '?'}',
              ),
              Text(
                'Sesión: ${_attempt!['recovery_id'] ?? 'inicio pendiente de respuesta'}',
              ),
              ExpansionTile(
                title: const Text('Diagnóstico y resultado del intento'),
                children: [
                  SelectableText(
                    const JsonEncoder.withIndent('  ').convert(
                      (_attempt!['progress'] as Map?)?['diagnostic'] ??
                          (_attempt!['progress'] as Map?)?['receipt'] ??
                          'Aún sin resultado remoto',
                    ),
                  ),
                ],
              ),
              if (!['completed', 'aborted'].contains(_attempt!['state'])) ...[
                OutlinedButton(
                  onPressed: _busy ? null : () => _transfer(),
                  child: const Text('Consultar y reanudar intento'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _transfer(abort: true),
                  child: const Text('Abortar antes de publicar'),
                ),
              ],
              if (_attempt!['state'] == 'ready_to_commit') ...[
                CheckboxListTile(
                  value: _confirmPublication,
                  onChanged: _busy
                      ? null
                      : (value) => setState(
                          () => _confirmPublication = value ?? false,
                        ),
                  title: const Text(
                    'Revisé el corte, las exclusiones, el diagnóstico y este destino. Confirmo publicar.',
                  ),
                ),
                FilledButton(
                  onPressed: _busy || !_confirmPublication
                      ? null
                      : () => _transfer(publish: true),
                  child: const Text('Publicar recuperación'),
                ),
              ],
              if (['completed', 'aborted'].contains(_attempt!['state']))
                OutlinedButton(
                  onPressed: _busy ? null : _archive,
                  child: const Text('Archivar intento conservando evidencia'),
                ),
              if (_attempt!['state'] == 'completed') ...[
                const Text(
                  'Publicación confirmada. Vincula este origen explícitamente con la credencial de alta emitida por el operador para esta generación.',
                ),
                TextField(
                  controller: _enrollment,
                  enabled: !_busy,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Credencial de alta del dispositivo',
                  ),
                ),
                CheckboxListTile(
                  value: _confirmBinding,
                  onChanged: _busy
                      ? null
                      : (value) =>
                            setState(() => _confirmBinding = value ?? false),
                  title: const Text(
                    'Confirmo sustituir esta base por el baseline validado, conservando el respaldo. Si cambió después del corte, se bloqueará la sustitución.',
                  ),
                ),
                FilledButton(
                  onPressed: _busy || !_confirmBinding ? null : _bind,
                  child: const Text('Vincular este origen y reabrir'),
                ),
              ],
            ],
            if (_history.isNotEmpty)
              ExpansionTile(
                title: const Text('Historial de intentos conservados'),
                children: [
                  for (final entry in _history)
                    ListTile(
                      title: Text(
                        '${entry['state']} · ${entry['destination']}',
                      ),
                      subtitle: Text('${entry['package_id']}'),
                      trailing: TextButton(
                        onPressed: _busy || _attempt != null
                            ? null
                            : () => _reopen(entry['key'] as String),
                        child: const Text('Reabrir'),
                      ),
                    ),
                ],
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }

  String _reason(String code) => switch (code) {
    'pending' => 'Hay eventos pendientes de entrega.',
    'application_failed' => 'Hay eventos con fallo de aplicación.',
    'unresolved_incident' => 'Hay conflictos o incidentes sin resolver.',
    'incompatible_event_contract' => 'Hay eventos con un formato incompatible.',
    'unaccredited_dependency' =>
      'Falta evidencia confirmada de una dependencia.',
    'shared_not_required' => 'Hay eventos compartidos sin entrega acreditada.',
    'destination_not_empty' => 'El destino ya contiene datos.',
    'active_recovery' =>
      'Ya existe una recuperación activa. Debe consultarse ese intento.',
    'incompatible_schema' => 'El esquema del destino no es compatible.',
    'standalone_not_supported' =>
      'Los datos de modo local no se convierten a sincronización.',
    'legacy_generation_unknown' =>
      'Se desconoce la generación del servidor de origen.',
    'global_server_completeness_unknown' =>
      'No se puede acreditar la totalidad del servidor perdido.',
    'no_full_pull_known' => 'No consta una descarga completa anterior.',
    'full_pull_date_unknown' =>
      'Se desconoce la fecha de la última descarga completa.',
    _ => code,
  };
}
