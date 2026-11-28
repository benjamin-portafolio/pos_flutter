import 'package:flutter/material.dart';

import '../../../application/config/app_config.dart';
import '../../../application/config/app_config_controller.dart';
import '../../../application/sync/models/sync_availability_snapshot.dart';
import '../../../application/sync/sync_status_controller.dart';
import '../../../core/di/injection.dart';

/// Refleja la sincronización observada; solo el botón de comprobación inicia red.
class ServerConnectionIndicator extends StatelessWidget {
  const ServerConnectionIndicator({
    super.key,
    this.compact = false,
    this.onOpen,
    this.onClose,
  });

  final bool compact;
  final Future<bool> Function()? onOpen;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final config = getIt<AppConfigController>();
    return StreamBuilder<AppConfig>(
      initialData: config.config,
      stream: config.changes,
      builder: (context, snapshot) {
        if (snapshot.data!.isStandalone) {
          return _buildStatus(
            context,
            Icons.computer,
            Colors.grey,
            'Modo local',
          );
        }
        final controller = getIt<SyncStatusController>();
        return AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final hasProblems =
                controller.error != null ||
                (controller.local?.problems.isNotEmpty ?? false);
            final offline =
                controller.availability.status ==
                SyncAvailabilityStatus.unavailable;
            return _buildStatus(
              context,
              hasProblems
                  ? Icons.warning_amber_rounded
                  : offline
                  ? Icons.cloud_off_outlined
                  : controller.isCurrent
                  ? Icons.cloud_done_outlined
                  : Icons.sync,
              hasProblems
                  ? Colors.red
                  : controller.isCurrent
                  ? Colors.green
                  : offline
                  ? Colors.grey
                  : Colors.orange,
              controller.label,
              onTap: () async {
                if (onOpen != null && !await onOpen!()) return;
                if (!context.mounted) return;
                try {
                  await showDialog<void>(
                    context: context,
                    builder: (_) => _SyncDetails(controller: controller),
                  );
                } finally {
                  onClose?.call();
                }
              },
            );
          },
        );
      },
    );
  }

  Widget _buildStatus(
    BuildContext context,
    IconData icon,
    Color color,
    String label, {
    VoidCallback? onTap,
  }) {
    final content = Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: compact ? 2 : null,
            overflow: compact ? TextOverflow.ellipsis : null,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
    return Tooltip(
      message: label,
      child: Material(
        color: color.withValues(alpha: 0.1),
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: compact
                ? BoxConstraints(
                    maxWidth: (MediaQuery.sizeOf(context).width * 0.4)
                        .clamp(0, 190)
                        .toDouble(),
                  )
                : null,
            width: compact ? null : double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 16,
              vertical: 12,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _SyncDetails extends StatelessWidget {
  const _SyncDetails({required this.controller});
  final SyncStatusController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final verified = controller.verifiedAt?.toLocal();
      final problems = controller.local?.problems;
      return AlertDialog(
        title: const Text('Sincronización de este dispositivo'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(controller.label),
                const SizedBox(height: 16),
                Text(
                  'Cambios por enviar: ${controller.local?.pending ?? 'Consultando…'}',
                ),
                Text(
                  'Recepción de cambios: ${controller.isCurrent
                      ? 'Al día'
                      : controller.busy
                      ? 'Comprobando…'
                      : 'Por comprobar'}',
                ),
                Text(
                  'Problemas por atender: ${problems?.length ?? 'Consultando…'}',
                ),
                const SizedBox(height: 12),
                Text(
                  verified == null
                      ? 'Sin comprobación vigente.'
                      : 'Última comprobación exitosa: ${MaterialLocalizations.of(context).formatShortDate(verified)} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(verified), alwaysUse24HourFormat: true)}',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Confirma este dispositivo con el servidor. Otros equipos pueden tener cambios pendientes de enviar.',
                ),
                if (controller.error != null) ...[
                  const SizedBox(height: 12),
                  Text(controller.error!),
                ],
                if (controller.availability.message != null &&
                    !controller.availability.isAvailable)
                  Text(controller.availability.message!),
                if (problems != null && problems.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Ver problemas'),
                    children: problems
                        .map(
                          (p) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(p.reason),
                            subtitle: SelectableText(
                              '${p.eventType}\n${p.eventId}',
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
          FilledButton(
            onPressed: controller.busy ? null : () => controller.checkNow(),
            child: const Text('Comprobar ahora'),
          ),
        ],
      );
    },
  );
}
