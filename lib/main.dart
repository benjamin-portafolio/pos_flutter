import 'package:flutter/material.dart';
import 'package:pos_flutter/application/sync/sync_orchestrator.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/presentation/pages/pantalla_principal/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  setupDependencyInjection();
  getIt<SyncOrchestrator>()
    ..startAutoPush()
    ..startRealtimeListener();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

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
      home: HomeScreen(),
    );
  }
}
