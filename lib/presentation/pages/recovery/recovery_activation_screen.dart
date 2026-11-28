import 'package:flutter/material.dart';

/// Blocks business screens until the initial pull is fully applied, for a new
/// device or a recovered generation. Failures preserve downloaded progress.
class RecoveryActivationScreen extends StatefulWidget {
  const RecoveryActivationScreen({
    required this.activate,
    required this.onActivated,
    this.initialSetup = false,
    super.key,
  });
  final Future<void> Function() activate;
  final VoidCallback onActivated;
  final bool initialSetup;
  @override
  State<RecoveryActivationScreen> createState() =>
      _RecoveryActivationScreenState();
}

class _RecoveryActivationScreenState extends State<RecoveryActivationScreen> {
  bool _busy = false;
  String? _error;
  bool _completed = false;
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
      if (!mounted) return;
      if (widget.initialSetup) {
        setState(() => _completed = true);
      } else {
        widget.onActivated();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = widget.initialSetup
              ? 'No se pudo completar la sincronización inicial. Comprueba la conexión y vuelve a intentar. Los datos y el progreso se conservan.'
              : 'No se completó la descarga de la nueva generación. Los datos y el progreso se conservan.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.initialSetup
              ? 'Sincronización inicial'
              : 'Activar dispositivo recuperado',
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
              ],
              if (_completed) ...[
                const Icon(Icons.check_circle_outline, size: 48),
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: const Text(
                    'Sincronización inicial completada. Ya puedes usar la app',
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: widget.onActivated,
                  child: const Text('Entrar'),
                ),
              ] else ...[
                Text(
                  widget.initialSetup
                      ? 'Preparando tus datos…'
                      : 'La base inicial está instalada. Se descargarán las operaciones posteriores a su corte antes de habilitar ventas y sincronización habitual.',
                  textAlign: TextAlign.center,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _run,
                    child: Text(
                      widget.initialSetup
                          ? 'Reintentar'
                          : 'Reintentar descarga y activar',
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
