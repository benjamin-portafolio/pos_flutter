import 'dart:async';
import 'package:flutter/material.dart';
import '../../../application/config/app_config_controller.dart';
import '../../../application/recovery/recovery_destination_inspector.dart';
import '../../../application/recovery/recovery_readiness_service.dart';
import '../../../application/sync/sync_availability_monitor.dart';
import '../../../application/sync/sync_network_gate.dart';
import '../../../application/sync/sync_socket_listener.dart';
import '../../../core/di/injection.dart';
import 'recovery_readiness_screen.dart';

/// Ambos accesos conservan setupCompleted y la identidad/modo instalados.
class RecoveryAccessTile extends StatefulWidget {
  const RecoveryAccessTile({this.enabled = true, super.key});
  final bool enabled;
  @override
  State<RecoveryAccessTile> createState() => _RecoveryAccessTileState();
}

class _RecoveryAccessTileState extends State<RecoveryAccessTile> {
  bool _opening = false;
  Future<void> _open() async {
    if (_opening || !widget.enabled) return;
    setState(() => _opening = true);
    final gate = getIt<SyncNetworkGate>();
    final monitor = getIt<SyncAvailabilityMonitor>();
    final wasStarted = monitor.isStarted;
    final mode = getIt<AppConfigController>().mode;
    // pause cierra admisión sin esperar: no hay ventana tras detener WS.
    final drained = gate.pause();
    try {
      getIt<SyncSocketListener>().stop();
      await monitor.stop();
      await drained.timeout(const Duration(seconds: 20));
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => RecoveryReadinessScreen(
            mode: mode,
            service: getIt<RecoveryReadinessService>(),
            inspector: getIt<RecoveryDestinationInspector>(),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo pausar la sincronización para abrir la revisión. Intenta nuevamente.',
            ),
          ),
        );
      }
    } finally {
      await monitor.stop();
      gate.resume();
      if (wasStarted && mounted) monitor.start();
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.settings_backup_restore),
    title: const Text('Recuperar servidor desde este dispositivo'),
    subtitle: const Text('Revisar origen y compatibilidad del destino'),
    onTap: _opening || !widget.enabled ? null : _open,
  );
}
