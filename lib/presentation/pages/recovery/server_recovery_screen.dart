import 'package:flutter/material.dart';
import '../../../application/config/app_config.dart';
import '../../../application/recovery/recovery_admin_client.dart';
import 'server_administration_form_screen.dart';

class ServerRecoveryScreen extends StatelessWidget {
  const ServerRecoveryScreen({
    super.key,
    this.client,
    this.mode,
    this.initialDestination,
  });
  final RecoveryAdminClient? client;
  final AppMode? mode;
  final String? initialDestination;

  @override
  Widget build(BuildContext context) => ServerAdministrationFormScreen(
    client: client,
    mode: mode,
    initialDestination: initialDestination,
    enrollment: false,
  );
}
