import 'package:flutter/material.dart';

import '../../../application/config/app_config.dart';
import '../../../application/config/app_config_controller.dart';
import '../../../application/recovery/recovery_admin_client.dart';
import '../../../core/di/injection.dart';
import 'server_administration_access.dart';
import 'server_recovery_screen.dart';
import 'server_device_enrollment_screen.dart';

class ServerAdministrationScreen extends StatelessWidget {
  const ServerAdministrationScreen({
    super.key,
    this.client,
    this.mode,
    this.initialDestination,
  });

  final RecoveryAdminClient? client;
  final AppMode? mode;
  final String? initialDestination;

  @override
  Widget build(BuildContext context) {
    final installedMode = mode ?? getIt<AppConfigController>().mode;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Administración del servidor')),
      body: !canAdministerServer(installedMode)
          ? const Center(
              child: Text('Disponible en computadora y en modo servidor.'),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      'Panel de administración',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Selecciona una herramienta para administrar el servidor.',
                    ),
                    const SizedBox(height: 24),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.devices),
                        title: const Text('Alta de dispositivos'),
                        subtitle: const Text(
                          'Permite descargar los datos del servidor y vincular instalaciones vacías.',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => ServerDeviceEnrollmentScreen(
                              client: client,
                              mode: installedMode,
                              initialDestination: initialDestination,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => ServerRecoveryScreen(
                                  client: client,
                                  mode: installedMode,
                                  initialDestination: initialDestination,
                                ),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.settings_backup_restore,
                                    size: 36,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Recuperación del servidor',
                                    style: theme.textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Prepara un servidor vacío y autoriza el dispositivo que recuperará sus datos.',
                                  ),
                                  const SizedBox(height: 24),
                                  Row(
                                    children: [
                                      Text(
                                        'Entrar',
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(
                                              color: theme.colorScheme.primary,
                                            ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.arrow_forward,
                                        size: 20,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
