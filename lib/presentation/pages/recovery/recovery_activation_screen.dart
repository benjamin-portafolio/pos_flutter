import 'package:flutter/material.dart';

/// Business screens stay unavailable until the first complete pull of the new
/// generation. A failure preserves the baseline, binding and partial progress.
class RecoveryActivationScreen extends StatefulWidget {
  const RecoveryActivationScreen({
    required this.activate,
    required this.onActivated,
    super.key,
  });
  final Future<void> Function() activate;
  final VoidCallback onActivated;
  @override
  State<RecoveryActivationScreen> createState() =>
      _RecoveryActivationScreenState();
}

class _RecoveryActivationScreenState extends State<RecoveryActivationScreen> {
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.activate();
      if (mounted) widget.onActivated();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se completó la descarga de la nueva generación. Los datos y el progreso se conservan.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Activar dispositivo recuperado')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'La base inicial está instalada. Se descargarán las operaciones posteriores a su corte antes de habilitar ventas y sincronización habitual.',
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          FilledButton(
            onPressed: _busy ? null : _run,
            child: const Text('Reintentar descarga y activar'),
          ),
        ],
      ),
    ),
  );
}
