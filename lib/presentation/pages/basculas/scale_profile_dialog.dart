import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../application/weighing/scale_device.dart';
import '../../../application/weighing/scale_exception.dart';
import '../../../application/weighing/scale_failure.dart';
import '../../../application/weighing/scale_gateway.dart';
import '../../../application/weighing/scale_profile.dart';
import '../../../application/weighing/scale_session_service.dart';
import 'scale_failure_message.dart';
import 'scale_test_screen.dart';

class ScaleProfileDialog extends StatefulWidget {
  const ScaleProfileDialog({
    super.key,
    required this.gateway,
    required this.service,
    required this.profiles,
    this.profile,
  });

  final ScaleGateway gateway;
  final ScaleSessionService service;
  final List<ScaleProfile> profiles;
  final ScaleProfile? profile;

  @override
  State<ScaleProfileDialog> createState() => _ScaleProfileDialogState();
}

class _ScaleProfileDialogState extends State<ScaleProfileDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _alias;
  late final String _id;
  List<ScaleDevice> _devices = [];
  ScaleDevice? _selected;
  bool _loading = false;
  String? _message;

  String _key(ScaleDevice device) =>
      '${device.port.trim().toUpperCase()}|${device.systemId.trim().toUpperCase()}';

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _alias = TextEditingController(text: profile?.alias ?? '');
    _id = profile?.id ?? const Uuid().v4();
    if (profile != null) {
      _selected = ScaleDevice(
        port: profile.port,
        name: profile.alias,
        systemId: profile.systemId,
      );
      _devices = [_selected!];
    }
  }

  @override
  void dispose() {
    _alias.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      if (widget.service.active != null) {
        throw const ScaleException(ScaleFailure.busy);
      }
      final devices = await widget.gateway.listDevices();
      if (!mounted) return;
      setState(() {
        final previous = _selected;
        _devices = devices;
        _selected = previous == null
            ? null
            : devices.where((d) => _key(d) == _key(previous)).firstOrNull;
        if (previous != null && _selected == null) {
          _message =
              'El destino anterior ya no aparece. Selecciona el puerto explícitamente.';
        } else if (devices.isEmpty) {
          _message =
              'No hay puertos disponibles. Conecta la báscula y actualiza.';
        }
      });
    } on ScaleException catch (error) {
      if (mounted) {
        setState(() => _message = scaleFailureMessage(error.failure));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'No se pudieron enumerar los puertos.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  ScaleProfile? _buildProfile() {
    if (!_form.currentState!.validate()) return null;
    if (widget.service.active != null) {
      setState(() => _message = scaleFailureMessage(ScaleFailure.busy));
      return null;
    }
    final selected = _selected!;
    return ScaleProfile(
      id: _id,
      alias: _alias.text,
      port: selected.port,
      systemId: selected.systemId,
    );
  }

  Future<void> _test() async {
    final profile = _buildProfile();
    if (profile == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ScaleTestScreen(profile: profile, service: widget.service),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.profile == null ? 'Agregar báscula' : 'Editar báscula'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _alias,
                decoration: const InputDecoration(labelText: 'Alias'),
                validator: (value) =>
                    value?.trim().isEmpty ?? true ? 'Escribe un alias.' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<ScaleModel>(
                initialValue: ScaleModel.rhinoBar8Rs,
                decoration: const InputDecoration(labelText: 'Modelo'),
                items: const [
                  DropdownMenuItem(
                    value: ScaleModel.rhinoBar8Rs,
                    child: Text('Rhino BAR-8RS'),
                  ),
                ],
                onChanged: (_) {},
              ),
              const SizedBox(height: 16),
              if (widget.profile case final profile?)
                Text('Destino guardado: ${profile.port}'),
              DropdownButtonFormField<String>(
                key: ValueKey(_selected == null ? null : _key(_selected!)),
                initialValue: _selected == null ? null : _key(_selected!),
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Puerto'),
                items: [
                  for (final device in _devices)
                    DropdownMenuItem(
                      value: _key(device),
                      child: Text(
                        '${device.port} · ${device.name}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _loading
                    ? null
                    : (value) => setState(() {
                        _selected = _devices
                            .where((d) => _key(d) == value)
                            .firstOrNull;
                      }),
                validator: (_) {
                  if (_selected == null) return 'Selecciona un puerto.';
                  if (widget.profiles.any(
                    (p) =>
                        p.id != _id &&
                        p.port == _selected!.port.trim().toUpperCase(),
                  )) {
                    return 'Ese puerto ya tiene un perfil.';
                  }
                  return null;
                },
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar puertos'),
              ),
              if (_loading) const LinearProgressIndicator(),
              if (_message != null) Text(_message!),
              if (_selected case final device?)
                Text('Identificador: ${device.systemId}'),
              const SizedBox(height: 12),
              const Text(
                '9600 baudios · 8 bits · sin paridad · 1 bit de parada · sin control de flujo',
              ),
              OutlinedButton(
                onPressed: _loading ? null : _test,
                child: const Text('Probar lectura'),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _loading
            ? null
            : () {
                final profile = _buildProfile();
                if (profile != null) Navigator.of(context).pop(profile);
              },
        child: const Text('Guardar'),
      ),
    ],
  );
}
