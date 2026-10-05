import 'package:pos_flutter/domain/articulos/variante_por_codigo_barras.dart';
import 'package:pos_flutter/domain/articulos/articulo_detalle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/backup/backup_service.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/config/app_config_store.dart';
import 'package:pos_flutter/application/sync/projections/cash_projection_store.dart';
import 'package:pos_flutter/application/sync/projections/cash_session_projection.dart';
import 'package:pos_flutter/application/sync/sync_availability_monitor.dart';
import 'package:pos_flutter/application/sync/sync_detection_settings_store.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_store.dart';
import 'package:pos_flutter/application/sync/sync_orchestrator.dart';
import 'package:pos_flutter/application/sync/sync_server_detection_config.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/domain/articulos/articulo_listado.dart';
import 'package:pos_flutter/domain/articulos/articulo_vinculado_categoria.dart';
import 'package:pos_flutter/domain/categorias/categoria.dart';
import 'package:pos_flutter/domain/repositories/categoria_repository.dart';
import 'package:pos_flutter/domain/repositories/producto_repository.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/inventory_management_screen.dart';
import 'package:pos_flutter/presentation/pages/pantalla_principal/menu_lateral.dart';
import 'package:pos_flutter/presentation/pages/pantalla_principal/sync_settings_page.dart';
import 'package:pos_flutter/presentation/pages/pantalla_principal/sync_settings_screen.dart';
import 'dart:async';

void main() {
  late _FakeSyncDetectionSettingsStore detectionSettingsStore;
  late SyncServerDetectionConfig serverDetectionConfig;
  late _FakeProductoRepository productoRepository;

  setUp(() async {
    await getIt.reset();
    detectionSettingsStore = _FakeSyncDetectionSettingsStore();
    serverDetectionConfig = SyncServerDetectionConfig();
    productoRepository = _FakeProductoRepository();
    addTearDown(productoRepository.varianteCounts.close);
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
    getIt.registerSingleton<ProductoRepository>(productoRepository);
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

    await tester.scrollUntilVisible(
      find.text('Configuracion'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
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

  testWidgets('el badge de inventarios muestra las variantes dadas de alta', (
    tester,
  ) async {
    final counts = productoRepository.varianteCounts;
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

    // El ListView del drawer es lazy: la entrada se construye al hacer scroll.
    await tester.scrollUntilVisible(
      find.text('Gestión de inventarios'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final inventoryTile = find.widgetWithText(
      ListTile,
      'Gestión de inventarios',
    );
    expect(
      find.descendant(of: inventoryTile, matching: find.text('0')),
      findsNothing,
    );

    counts.add(7);
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: inventoryTile, matching: find.text('7')),
      findsOneWidget,
    );

    counts.add(1);
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: inventoryTile, matching: find.text('1')),
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

  testWidgets('el menu muestra caja solo con la captura habilitada', (
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

    expect(find.text('Apertura y corte de caja'), findsOneWidget);

    getIt<AppConfigController>().update(
      getIt<AppConfigController>().config.copyWith(cashEnabled: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('Apertura y corte de caja'), findsNothing);
  });

  testWidgets('Configuracion cambia la captura de caja de la instalacion', (
    tester,
  ) async {
    final saved = <AppConfig>[];
    getIt.registerSingleton<AppConfigStore>(_FakeAppConfigStore(saved));
    getIt.registerSingleton<LocalCommandContext>(
      const LocalCommandContext(deviceId: 'device-1', userId: 'user-1'),
    );
    getIt.registerSingleton<CashProjectionStore>(_FakeCashProjectionStore());
    final controller = getIt<AppConfigController>();

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SyncSettingsScreen())),
    );

    final tile = find.widgetWithText(SwitchListTile, 'Corte de caja');
    await tester.scrollUntilVisible(
      tile,
      200,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();

    expect(
      tester.widget<SwitchListTile>(tile).value,
      controller.config.cashEnabled,
    );

    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(controller.config.cashEnabled, isFalse);
    expect(saved.single.cashEnabled, isFalse);
  });

  testWidgets('Configuracion no cambia la captura con caja abierta', (
    tester,
  ) async {
    final saved = <AppConfig>[];
    getIt.registerSingleton<AppConfigStore>(_FakeAppConfigStore(saved));
    getIt.registerSingleton<LocalCommandContext>(
      const LocalCommandContext(deviceId: 'device-1', userId: 'user-1'),
    );
    getIt.registerSingleton<CashProjectionStore>(
      _FakeCashProjectionStore(openSession: true),
    );
    final controller = getIt<AppConfigController>();

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SyncSettingsScreen())),
    );

    final tile = find.widgetWithText(SwitchListTile, 'Corte de caja');
    await tester.scrollUntilVisible(
      tile,
      200,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();

    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(controller.config.cashEnabled, isTrue);
    expect(saved, isEmpty);
    expect(
      find.text('Cierra la caja de esta terminal antes de cambiar el ajuste.'),
      findsOneWidget,
    );
  });
}

class _FakeAppConfigStore implements AppConfigStore {
  _FakeAppConfigStore(this.saved);
  final List<AppConfig> saved;

  @override
  Future<AppConfig> readConfig() async => AppConfig.initial;

  @override
  Future<void> saveConfig(AppConfig config) async => saved.add(config);
}

class _FakeCashProjectionStore implements CashProjectionStore {
  _FakeCashProjectionStore({this.openSession = false});
  final bool openSession;

  @override
  Future<CashSessionProjection?> current(String deviceId) async => openSession
      ? CashSessionProjection(
          id: 'session-1',
          active: true,
          version: 1,
          createdEventId: 'event-1',
          lastEventId: 'event-1',
          lastServerSequence: null,
          deviceId: deviceId,
          openedByUserId: 'user-1',
          status: 'open',
          openedAtMs: 0,
          openingMinor: 0,
        )
      : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

class _FakeProductoRepository implements ProductoRepository {
  @override
  Future<List<VariantePorCodigoBarras>> buscarVariantesPorCodigoBarras(
    String codigo,
  ) async => const [];

  // Un controlador sin oyentes también debe poder cerrarse en tearDown.
  _FakeProductoRepository()
    : varianteCounts = StreamController<int>.broadcast();

  /// Emisiones sucesivas del conteo de variantes; cada una rebuilds el badge.
  final StreamController<int> varianteCounts;

  @override
  Future<ArticuloDetalle?> obtenerDetalle(String productoId) async => null;

  @override
  Future<List<ArticuloVinculadoCategoria>> obtenerArticulosPorCategoria(
    String categoriaId,
  ) async => const [];

  @override
  Stream<List<ArticuloListado>> watchArticulos({
    String busqueda = '',
    Set<String> categoriaIds = const <String>{},
    bool incluirSinCategoria = false,
  }) {
    return Stream.value(const []);
  }

  @override
  Stream<int> watchVariantesActivasCount() => varianteCounts.stream;
}
