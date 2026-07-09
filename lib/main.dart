import 'package:flutter/material.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/sync_availability_monitor.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/presentation/onboarding/first_run_setup_screen.dart';
import 'package:pos_flutter/presentation/pages/pantalla_principal/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bootstrap = await setupDependencyInjection();
  if (bootstrap.appConfig.isServerSync) {
    getIt<SyncAvailabilityMonitor>().start();
  }
  runApp(MainApp(initialConfig: bootstrap.appConfig));
}

class MainApp extends StatelessWidget {
  const MainApp({super.key, this.initialConfig});

  final AppConfig? initialConfig;

  @override
  Widget build(BuildContext context) {
    /* return const MaterialApp(
      home: Scaffold(body: Center(child: Text('Hello World!'))),
    );*/
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Seleccionar Mesa',
      theme: ThemeData(primarySwatch: Colors.blue),
      // home: TestDependencia(dependencia: dependencia),
      // home: ListTestScreen(),
      // home: ValueNotifierExampleScreen(),
      home: _initialHome(),
    );
  }

  Widget _initialHome() {
    final config =
        initialConfig ??
        (getIt.isRegistered<AppConfigController>()
            ? getIt<AppConfigController>().config
            : AppConfig.initial.copyWith(setupCompleted: true));

    if (!config.setupCompleted) {
      return const FirstRunSetupScreen();
    }

    return const HomeScreen();
  }
}
