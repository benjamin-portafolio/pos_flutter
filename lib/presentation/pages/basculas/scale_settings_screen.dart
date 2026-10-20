import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../application/weighing/scale_exception.dart';
import '../../../application/weighing/scale_failure.dart';
import '../../../application/weighing/scale_gateway.dart';
import '../../../application/weighing/scale_profile.dart';
import '../../../application/weighing/scale_session.dart';
import '../../../application/weighing/scale_session_service.dart';
import '../../../application/weighing/scale_settings.dart';
import '../../../application/weighing/scale_settings_controller.dart';
import '../../../application/weighing/scale_settings_exception.dart';
import 'scale_failure_message.dart';
import 'scale_profile_dialog.dart';
import 'scale_test_screen.dart';

class ScaleSettingsScreen extends StatefulWidget {
  const ScaleSettingsScreen({
    super.key,
    required this.controller,
    required this.gateway,
    required this.service,
  });

  final ScaleSettingsController controller;
  final ScaleGateway gateway;
  final ScaleSessionService service;

  @override
  State<ScaleSettingsScreen> createState() => _ScaleSettingsScreenState();
}

class _ScaleSettingsScreenState extends State<ScaleSettingsScreen> {
  late final StreamSubscription<ScaleSettings> _subscription;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.controller.changes.listen((_) {
      if (mounted) setState(() {});
    });
    if (!widget.controller.loaded) _run(widget.controller.load);
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }

  void _notice(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _run(Future<void> Function() operation) async {
    setState(() => _working = true);
    try {
      await operation();
    } on ScaleException catch (error) {
      if (mounted) _notice(scaleFailureMessage(error.failure));
    } on ArgumentError {
      if (mounted) {
        _notice('Ese destino ya tiene un perfil o la selección no es válida.');
      }
    } catch (_) {
      if (mounted) {
        _notice(
          'No se pudieron guardar los ajustes. Se conserva el último estado confirmado.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  bool _checkIdle() {
    if (widget.service.active == null) return true;
    _notice(scaleFailureMessage(ScaleFailure.busy));
    return false;
  }

  Future<void> _edit([ScaleProfile? existing]) async {
    if (!_checkIdle()) return;
    final profile = await showDialog<ScaleProfile>(
      context: context,
      builder: (_) => ScaleProfileDialog(
        gateway: widget.gateway,
        service: widget.service,
        profiles: widget.controller.settings.profiles,
        profile: existing,
      ),
    );
    if (mounted && profile != null) {
      await _run(() => widget.controller.upsert(profile));
    }
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _remove(ScaleProfile profile) async {
    if (!_checkIdle()) return;
    if (!await _confirm(
      'Quitar báscula',
      'Quitar ${profile.alias} (${profile.port}) de esta app. Si es la predeterminada, la selección quedará vacía.',
      'Quitar',
    )) {
      return;
    }
    if (mounted) await _run(() => widget.controller.remove(profile.id));
  }

  Future<void> _recover() async {
    if (!_checkIdle()) return;
    if (!await _confirm(
      'Recuperar configuración',
      'Se conservará una copia del archivo original y se creará una configuración vacía. Deberás agregar las básculas de nuevo.',
      'Conservar y reiniciar',
    )) {
      return;
    }
    if (mounted) {
      await _run(() async {
        final archive = await widget.controller.recover();
        if (mounted) _notice('Original conservado en: $archive');
      });
    }
  }

  Future<void> _test(ScaleProfile profile) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ScaleTestScreen(profile: profile, service: widget.service),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final settings = controller.settings;
    final canEdit = controller.canEdit && !_working;
    final active = widget.service.active;
    return Scaffold(
      appBar: AppBar(title: const Text('Básculas')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Básculas de esta instalación. Configuración local disponible en ambos modos. Guardar un perfil no lo conecta.',
          ),
          if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows)
            Text(scaleFailureMessage(ScaleFailure.unsupportedPlatform)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: canEdit ? _edit : null,
            icon: const Icon(Icons.add),
            label: const Text('Agregar báscula'),
          ),
          if (_working) const LinearProgressIndicator(),
          if (controller.loadError case final error?) ...[
            const SizedBox(height: 16),
            Text(switch (error.failure) {
              ScaleSettingsFailure.corrupt =>
                'El archivo de básculas está dañado. El original se conserva hasta la recuperación explícita.',
              ScaleSettingsFailure.unsupportedVersion =>
                'La versión del archivo de básculas no es compatible. El original se conserva hasta la recuperación explícita.',
              _ =>
                'No se pudo leer la configuración de básculas. Intenta recargar.',
            }),
            OutlinedButton(
              onPressed: _working ? null : () => _run(controller.load),
              child: const Text('Recargar configuración'),
            ),
            if (error.canRecover)
              OutlinedButton(
                onPressed: _working ? null : _recover,
                child: const Text('Recuperar configuración'),
              ),
          ],
          if (active?.owner == ScaleSessionOwner.test &&
              active?.snapshot.failure == ScaleFailure.closeFailed)
            OutlinedButton(
              onPressed: _working ? null : () => _run(active!.close),
              child: const Text('Reintentar cierre de prueba'),
            ),
          const SizedBox(height: 16),
          Text(
            settings.defaultId == null
                ? 'Sin báscula predeterminada.'
                : 'Predeterminada: ${settings.profiles.firstWhere((p) => p.id == settings.defaultId).alias}',
          ),
          if (settings.defaultId != null)
            TextButton(
              onPressed: canEdit
                  ? () => _run(() => controller.setDefault(null))
                  : null,
              child: const Text('Dejar sin predeterminada'),
            ),
          if (settings.profiles.isEmpty &&
              controller.loadError == null &&
              !_working)
            const Text('No hay básculas guardadas.'),
          for (final profile in settings.profiles)
            Card(
              key: ValueKey(profile.id),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.alias,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text('Rhino BAR-8RS · ${profile.port} · 9600 / 8N1'),
                    if (settings.defaultId == profile.id)
                      const Text('Predeterminada'),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: canEdit ? () => _edit(profile) : null,
                          child: const Text('Editar'),
                        ),
                        TextButton(
                          onPressed: canEdit && settings.defaultId != profile.id
                              ? () => _run(
                                  () => controller.setDefault(profile.id),
                                )
                              : null,
                          child: const Text('Elegir predeterminada'),
                        ),
                        TextButton(
                          onPressed: canEdit ? () => _remove(profile) : null,
                          child: const Text('Quitar'),
                        ),
                        OutlinedButton(
                          onPressed: canEdit ? () => _test(profile) : null,
                          child: const Text('Probar lectura'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
