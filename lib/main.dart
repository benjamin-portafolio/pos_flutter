import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pos_flutter/application/backup/backup_scheduler.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/presentation/app/app_restart_scope.dart';
import 'package:pos_flutter/presentation/onboarding/first_run_setup_screen.dart';
import 'package:pos_flutter/presentation/pages/pantalla_principal/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bootstrap = await setupDependencyInjection();
  await startConfiguredRuntimeServices(bootstrap.appConfig);
  runApp(
    AppRestartScope(
      initialConfig: bootstrap.appConfig,
      builder: (config) => MainApp(initialConfig: config),
    ),
  );
}

class MainApp extends StatefulWidget {
  const MainApp({super.key, this.initialConfig});

  final AppConfig? initialConfig;

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final config = getIt.isRegistered<AppConfigController>()
        ? getIt<AppConfigController>().config
        : widget.initialConfig;
    if (state == AppLifecycleState.resumed &&
        config?.setupCompleted == true &&
        config?.usesGoogleDriveBackup == true &&
        getIt.isRegistered<BackupScheduler>()) {
      unawaited(getIt<BackupScheduler>().runDueBackup());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Seleccionar Mesa',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: _initialHome(),
    );
  }

  Widget _initialHome() {
    final config =
        widget.initialConfig ??
        (getIt.isRegistered<AppConfigController>()
            ? getIt<AppConfigController>().config
            : AppConfig.initial.copyWith(setupCompleted: true));

    if (!config.setupCompleted) {
      return const FirstRunSetupScreen();
    }

    return const HomeScreen();
  }
}
