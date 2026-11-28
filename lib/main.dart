import 'package:pos_flutter/application/config/app_config_store.dart';
import 'package:pos_flutter/application/sync/sync_installation.dart';
import 'package:pos_flutter/application/sync/sync_pull_service.dart';
import 'package:pos_flutter/presentation/pages/recovery/recovery_activation_screen.dart';
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
  final DependencyBootstrap bootstrap;
  try {
    bootstrap = await setupDependencyInjection();
    await startConfiguredRuntimeServices(bootstrap.appConfig);
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        context: ErrorDescription('al iniciar el POS'),
      ),
    );
    runApp(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No se pudo iniciar el POS. Consulta el registro de arranque '
                'para identificar el problema.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
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
  AppConfig? _activatedConfig;

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
        _activatedConfig ??
        widget.initialConfig ??
        (getIt.isRegistered<AppConfigController>()
            ? getIt<AppConfigController>().config
            : AppConfig.initial.copyWith(setupCompleted: true));

    final initialSync = config.isServerSync && config.initialSyncPending;
    if (initialSync ||
        (getIt.isRegistered<SyncInstallation>() &&
            getIt<SyncInstallation>().needsPull)) {
      return RecoveryActivationScreen(
        initialSetup: initialSync,
        activate: () async {
          await getIt<SyncPullService>().pullAvailableEvents();
          if (getIt.isRegistered<SyncInstallation>()) {
            await getIt<SyncInstallation>().activate();
          }
          if (initialSync) {
            final ready = getIt<AppConfigController>().config.copyWith(
              initialSyncPending: false,
            );
            await getIt<AppConfigStore>().saveConfig(ready);
            getIt<AppConfigController>().update(ready);
          }
        },
        onActivated: () {
          final ready = config.copyWith(initialSyncPending: false);
          setState(() => _activatedConfig = ready);
          unawaited(startConfiguredRuntimeServices(ready));
        },
      );
    }
    if (!config.setupCompleted) {
      return const FirstRunSetupScreen();
    }

    return const HomeScreen();
  }
}
