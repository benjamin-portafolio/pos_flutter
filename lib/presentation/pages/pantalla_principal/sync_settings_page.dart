import 'package:flutter/material.dart';

import 'sync_settings_screen.dart';

class SyncSettingsPage extends StatelessWidget {
  const SyncSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuracion')),
      body: const SyncSettingsScreen(),
    );
  }
}
