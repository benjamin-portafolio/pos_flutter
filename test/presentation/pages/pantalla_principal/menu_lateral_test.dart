import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/backup/backup_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/sync_availability_monitor.dart';
import 'package:pos_flutter/application/sync/sync_detection_settings_store.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_store.dart';
import 'package:pos_flutter/application/sync/sync_orchestrator.dart';
import 'package:pos_flutter/application/sync/sync_server_detection_config.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/domain/categorias/categoria.dart';
import 'package:pos_flutter/domain/repositories/categoria_repository.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/inventory_management_screen.dart';
import 'package:pos_flutter/presentation/pages/pantalla_principal/menu_lateral.dart';
import 'package:pos_flutter/presentation/pages/pantalla_principal/sync_settings_page.dart';
import 'package:pos_flutter/presentation/pages/pantalla_principal/sync_settings_screen.dart';

void main() {
  late _FakeSyncDetectionSettingsStore detectionSettingsStore;
  late SyncServerDetectionConfig serverDetectionConfig;

  setUp(() async {
    await getIt.reset();
    detectionSettingsStore = _FakeSyncDetectionSettingsStore();
    serverDetectionConfig = SyncServerDetectionConfig();
    final appConfig = AppConfig.initial.copyWith(
      mode: AppMode.serverSync,
      setupCompleted: true,
    );

    getIt.registerSingleton<AppConfigController>(
      AppConfigController(appConfig),
    );
    getIt.registerSingleton<SyncEndpointConfig>(SyncEndpointConfig());
    getIt.registerSingleton<SyncEndpointStore>(_FakeSyncEndpointStore());
    getIt.registerSingleton<SyncDetectionSettingsStore>(detectionSettingsStore);
    getIt.registerSingleton<SyncServerDetectionConfig>(serverDetectionConfig);
    getIt.registerSingleton<SyncAvailabilityMonitor>(
      _FakeSyncAvailabilityMonitor(),
    );
    getIt.registerSingleton<SyncOrchestrator>(_FakeSyncOrchestrator());
    getIt.registerSingleton<DatabaseStateReader>(_FakeDatabaseStateReader());
    getIt.registerSingleton<CategoriaRepository>(_FakeCategoriaRepository());
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('Configuracion opens settings as a full page', (tester) async {
    final scaffoldKey = GlobalKey<ScaffoldState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          key: scaffoldKey,
          drawer: const MenuLateral(),
          body: const SizedBox.shrink(),
        ),
      ),
    );

    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Configuracion'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Configuracion'));
    await tester.pumpAndSettle();

    expect(find.byType(SyncSettingsPage), findsOneWidget);
    expect(find.byType(SyncSettingsScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Configuracion'), findsOneWidget);
  });

  testWidgets('Gestión de inventarios opens inventory management', (
    tester,
  ) async {
    final scaffoldKey = GlobalKey<ScaffoldState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          key: scaffoldKey,
          drawer: const MenuLateral(),
          body: const SizedBox.shrink(),
        ),
      ),
    );

    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Gestión de inventarios'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gestión de inventarios'));
    await tester.pumpAndSettle();

    expect(find.byType(InventoryManagementScreen), findsOneWidget);
    expect(
      find.widgetWithText(AppBar, 'GESTIÓN DEL INVENTARIO'),
      findsOneWidget,
    );
  });

  testWidgets('Sync settings persists wifi detection preference', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SyncSettingsScreen())),
    );

    final wifiSwitch = find.text('Detectar servidor solo con WiFi');

    await tester.scrollUntilVisible(
      wifiSwitch,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(wifiSwitch);
    await tester.pumpAndSettle();

    expect(detectionSettingsStore.savedValues, [true]);
    expect(serverDetectionConfig.requireWifiForServerDetection, isTrue);
  });

  testWidgets('Sync settings shows installed mode without mode selector', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SyncSettingsScreen())),
    );

    expect(find.byType(DropdownButtonFormField<AppMode>), findsNothing);
    expect(find.text('Modo de operacion'), findsOneWidget);
    expect(find.text('Servidor'), findsOneWidget);
    expect(find.text('Instalado'), findsOneWidget);
    expect(
      find.text('El modo de operacion queda fijo despues de la instalacion.'),
      findsOneWidget,
    );
    expect(find.text('Guardar configuracion local'), findsNothing);
  });
}

class _FakeSyncEndpointStore implements SyncEndpointStore {
  @override
  Future<String?> readBaseUrl() async => null;

  @override
  Future<void> saveBaseUrl(String baseUrl) async {}
}

class _FakeSyncDetectionSettingsStore implements SyncDetectionSettingsStore {
  final savedValues = <bool>[];

  @override
  Future<bool> readRequireWifiForServerDetection() async => false;

  @override
  Future<void> saveRequireWifiForServerDetection(bool enabled) async {
    savedValues.add(enabled);
  }
}

class _FakeSyncAvailabilityMonitor implements SyncAvailabilityMonitor {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSyncOrchestrator implements SyncOrchestrator {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDatabaseStateReader implements DatabaseStateReader {
  @override
  Future<DatabaseState> readState() async {
    return const DatabaseState(eventCount: 0, lastLocalSequence: 0);
  }
}

class _FakeCategoriaRepository implements CategoriaRepository {
  @override
  Future<List<Categoria>> obtenerCategorias() async => const [];

  @override
  Stream<List<Categoria>> watchCategorias() => Stream.value(const []);
}
