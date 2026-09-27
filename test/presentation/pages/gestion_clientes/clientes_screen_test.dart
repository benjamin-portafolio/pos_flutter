import 'dart:async';
import 'package:pos_flutter/application/sync/projections/cliente_projection_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/clientes/cliente_command_service.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/domain/clientes/cliente.dart';
import 'package:pos_flutter/domain/clientes/cliente_resumen.dart';
import 'package:pos_flutter/domain/creditos/customer_account.dart';
import 'package:pos_flutter/domain/repositories/cliente_repository.dart';
import 'package:pos_flutter/domain/repositories/cliente_resumen_repository.dart';
import 'package:pos_flutter/domain/repositories/confirmed_sale_repository.dart';
import 'package:pos_flutter/domain/repositories/customer_account_repository.dart';
import 'package:pos_flutter/domain/ventas/confirmed_sale.dart';
import 'package:pos_flutter/presentation/pages/gestion_clientes/cliente_account_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_clientes/cliente_form_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_clientes/clientes_screen.dart';

void main() {
  testWidgets(
    'lista vacía, botón abajo a la izquierda, valida nombre y vuelve al listado',
    (tester) async {
      final store = _Clients();
      addTearDown(store.close);
      await tester.pumpWidget(
        MaterialApp(
          home: ClientesScreen(
            repository: store,
            resumenRepository: store,
            commandService: ClienteCommandService(
              clienteProjectionStore: store,
              eventStore: store,
              commandContext: const LocalCommandContext(
                deviceId: 'tablet',
                userId: 'user',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNothing);
      expect(find.text('Aún no hay clientes.'), findsOneWidget);
      final button = find.byType(FloatingActionButton);
      expect(tester.getCenter(button).dx, lessThan(400));
      expect(tester.getCenter(button).dy, greaterThan(450));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNWidgets(2));
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('El nombre es obligatorio.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('cliente_nombre')), ' Ana ');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.byType(ClienteFormScreen), findsNothing);
      expect(find.text('Ana'), findsOneWidget);
      expect(store.events.single.payload, {'nombre': 'Ana', 'telefono': null});
    },
  );
  testWidgets('cancelar no guarda; permite teléfono único como texto', (
    tester,
  ) async {
    final store = _Clients();
    addTearDown(store.close);
    await tester.pumpWidget(
      MaterialApp(
        home: ClientesScreen(
          repository: store,
          resumenRepository: store,
          commandService: ClienteCommandService(
            clienteProjectionStore: store,
            eventStore: store,
            commandContext: const LocalCommandContext(
              deviceId: 'tablet',
              userId: 'user',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cliente_nombre')), 'Cancelar');
    await tester.tap(find.byTooltip('Cancelar'));
    await tester.pumpAndSettle();
    expect(store.events, isEmpty);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cliente_nombre')), 'Luis');
    await tester.enterText(
      find.byKey(const Key('cliente_telefono')),
      '+52 00123',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Luis'), findsOneWidget);
    expect(find.text('+52 00123'), findsOneWidget);
  });
  testWidgets('mantiene datos ante error y evita doble guardado', (
    tester,
  ) async {
    final completer = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ClienteFormScreen(
          onSave: (_) {
            calls++;
            return completer.future;
          },
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('cliente_nombre')), 'Ana');
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    await tester.tap(find.text('Guardando…'));
    await tester.pump();
    expect(calls, 1);
    completer.completeError(StateError('storage'));
    await tester.pumpAndSettle();
    expect(find.text('Ana'), findsOneWidget);
    expect(
      find.text('No se pudo guardar el cliente. Inténtalo nuevamente.'),
      findsOneWidget,
    );
    expect(find.text('Guardar'), findsOneWidget);
  });
  testWidgets('formulario funciona en pantalla pequeña con teclado visible', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(home: ClienteFormScreen(onSave: (_) async {})),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('cliente_telefono')));
    await tester.enterText(find.byKey(const Key('cliente_telefono')), '00123');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'buscador siempre visible, pestañas y búsqueda ignorando mayúsculas y acentos',
    (tester) async {
      final store = _Clients();
      addTearDown(store.close);
      store.seedResumen([
        _resumen(id: 'a', nombre: 'Ana López'),
        _resumen(id: 'b', nombre: 'José Álvarez'),
        _resumen(id: 'c', nombre: 'María Hernández'),
      ]);
      await _pumpClientes(tester, store);
      expect(find.byKey(const Key('clientes_search_field')), findsOneWidget);
      expect(find.text('Todos los clientes'), findsOneWidget);
      expect(find.text('Clientes con adeudo'), findsOneWidget);
      expect(find.text('Ana López'), findsOneWidget);
      expect(find.text('José Álvarez'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('clientes_search_field')),
        'JOSE',
      );
      await tester.pumpAndSettle();
      expect(find.text('José Álvarez'), findsOneWidget);
      expect(find.text('Ana López'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('clientes_search_field')),
        'alv',
      );
      await tester.pumpAndSettle();
      expect(find.text('José Álvarez'), findsOneWidget);

      await tester.tap(find.byKey(const Key('clientes_search_clear')));
      await tester.pumpAndSettle();
      expect(find.text('Ana López'), findsOneWidget);
      expect(find.text('María Hernández'), findsOneWidget);
    },
  );

  testWidgets('la búsqueda se conserva al cambiar de pestaña', (tester) async {
    final store = _Clients();
    addTearDown(store.close);
    store.seedResumen([
      _resumen(id: 'a', nombre: 'Ana', saldo: -BigInt.from(500)),
      _resumen(id: 'b', nombre: 'Benito', saldo: -BigInt.from(200)),
    ]);
    await _pumpClientes(tester, store);
    await tester.enterText(
      find.byKey(const Key('clientes_search_field')),
      'ana',
    );
    await tester.tap(find.text('Clientes con adeudo'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cliente_resumen_a')), findsOneWidget);
    expect(find.byKey(const ValueKey('cliente_resumen_b')), findsNothing);
  });

  testWidgets(
    'pestaña de adeudos solo muestra deudores del mayor al menor adeudo',
    (tester) async {
      final store = _Clients();
      addTearDown(store.close);
      store.seedResumen([
        _resumen(id: 'a', nombre: 'Ana', saldo: -BigInt.from(500)),
        _resumen(id: 'b', nombre: 'Benito', saldo: -BigInt.from(50)),
        _resumen(id: 'c', nombre: 'Carlos', saldo: -BigInt.from(5000)),
        _resumen(id: 'd', nombre: 'Diana'),
        _resumen(id: 'e', nombre: 'Ernesto', saldo: BigInt.from(200)),
      ]);
      await _pumpClientes(tester, store);
      await tester.tap(find.text('Clientes con adeudo'));
      await tester.pumpAndSettle();
      expect(find.text('DEBE'), findsNWidgets(3));
      final carlosY = tester.getTopLeft(find.text('Carlos')).dy;
      final anaY = tester.getTopLeft(find.text('Ana')).dy;
      final benitoY = tester.getTopLeft(find.text('Benito')).dy;
      expect(carlosY, lessThan(anaY));
      expect(anaY, lessThan(benitoY));
      expect(find.byKey(const ValueKey('cliente_resumen_d')), findsNothing);
      expect(find.byKey(const ValueKey('cliente_resumen_e')), findsNothing);
    },
  );

  testWidgets('al liquidar la deuda el cliente desaparece de la pestaña', (
    tester,
  ) async {
    final store = _Clients();
    addTearDown(store.close);
    store.seedResumen([
      _resumen(id: 'a', nombre: 'Ana', saldo: -BigInt.from(500)),
      _resumen(id: 'b', nombre: 'Benito', saldo: -BigInt.from(50)),
    ]);
    await _pumpClientes(tester, store);
    await tester.tap(find.text('Clientes con adeudo'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cliente_resumen_a')), findsOneWidget);

    store.seedResumen([
      _resumen(id: 'a', nombre: 'Ana'),
      _resumen(id: 'b', nombre: 'Benito', saldo: -BigInt.from(50)),
    ]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cliente_resumen_a')), findsNothing);
    expect(find.byKey(const ValueKey('cliente_resumen_b')), findsOneWidget);

    store.seedResumen([_resumen(id: 'a', nombre: 'Ana')]);
    await tester.pumpAndSettle();
    expect(find.text('No hay clientes con adeudo.'), findsOneWidget);
  });

  testWidgets('estados vacíos: sin clientes y sin adeudos', (tester) async {
    final store = _Clients();
    addTearDown(store.close);
    await _pumpClientes(tester, store);
    expect(find.text('Aún no hay clientes.'), findsOneWidget);

    store.seedResumen([_resumen(id: 'a', nombre: 'Ana')]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clientes con adeudo'));
    await tester.pumpAndSettle();
    expect(find.text('No hay clientes con adeudo.'), findsOneWidget);
  });

  testWidgets('búsqueda sin coincidencias', (tester) async {
    final store = _Clients();
    addTearDown(store.close);
    store.seedResumen([_resumen(id: 'a', nombre: 'Ana')]);
    await _pumpClientes(tester, store);
    await tester.enterText(
      find.byKey(const Key('clientes_search_field')),
      'zzz',
    );
    await tester.pumpAndSettle();
    expect(find.text('No hay clientes que coincidan.'), findsOneWidget);
  });

  testWidgets('cliente inactivo muestra aviso de incidencia', (tester) async {
    final store = _Clients();
    addTearDown(store.close);
    store.seedResumen([_resumen(id: 'a', nombre: 'Ana', active: false)]);
    await _pumpClientes(tester, store);
    expect(
      find.text('Cuenta con incidencia · consultar historial'),
      findsOneWidget,
    );
  });

  testWidgets('tocar una tarjeta abre la cuenta del cliente', (tester) async {
    getIt.registerSingleton<CustomerAccountRepository>(_AccountFake());
    getIt.registerSingleton<ConfirmedSaleRepository>(_SalesFake());
    addTearDown(() => getIt.reset());
    final store = _Clients();
    addTearDown(store.close);
    store.seedResumen([_resumen(id: 'a', nombre: 'Ana')]);
    await _pumpClientes(tester, store);
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    expect(find.byType(ClienteAccountScreen), findsOneWidget);
  });
}

Future<void> _pumpClientes(WidgetTester tester, _Clients store) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ClientesScreen(
        repository: store,
        resumenRepository: store,
        commandService: ClienteCommandService(
          clienteProjectionStore: store,
          eventStore: store,
          commandContext: const LocalCommandContext(
            deviceId: 'tablet',
            userId: 'user',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ClienteResumen _resumen({
  required String id,
  required String nombre,
  String? telefono,
  bool active = true,
  BigInt? saldo,
}) => ClienteResumen(
  id: id,
  nombre: nombre,
  telefono: telefono,
  active: active,
  compras: 0,
  ultimoMovimiento: null,
  saldoMinor: saldo ?? BigInt.zero,
);

class _AccountFake implements CustomerAccountRepository {
  @override
  Stream<CustomerAccount> watchAccount(String clienteId) =>
      Stream.value(CustomerAccount(const []));
}

class _SalesFake implements ConfirmedSaleRepository {
  @override
  Stream<List<ConfirmedSale>> watchSales() => Stream.value(const []);
}

class _Clients
    implements
        ClienteRepository,
        LocalEventStore,
        ClienteProjectionStore,
        ClienteResumenRepository {
  final events = <SyncEvent>[];
  final _changes = StreamController<List<Cliente>>.broadcast();
  final _resumenChanges = StreamController<List<ClienteResumen>>.broadcast();
  final _rows = <Cliente>[];
  final _resumenRows = <ClienteResumen>[];

  @override
  Stream<List<Cliente>> watchClientes() async* {
    yield List.of(_rows);
    yield* _changes.stream;
  }

  @override
  Stream<List<ClienteResumen>> watchResumen() async* {
    yield List.of(_resumenRows);
    yield* _resumenChanges.stream;
  }

  void seedResumen(List<ClienteResumen> rows) {
    _resumenRows
      ..clear()
      ..addAll(rows);
    _resumenChanges.add(List.of(_resumenRows));
  }

  @override
  Future<void> appendAndApply(
    SyncEvent event, {
    required List<LocalEventRef> refs,
  }) async {
    events.add(event);
    final nombre = event.payload['nombre'] as String;
    final telefono = event.payload['telefono'] as String?;
    _rows.add(Cliente(id: event.aggregateId, nombre: nombre, telefono: telefono));
    _resumenRows.add(
      ClienteResumen(
        id: event.aggregateId,
        nombre: nombre,
        telefono: telefono,
        active: true,
        compras: 0,
        ultimoMovimiento: null,
        saldoMinor: BigInt.zero,
      ),
    );
    _changes.add(List.of(_rows));
    _resumenChanges.add(List.of(_resumenRows));
  }

  Future<void> close() async {
    await _changes.close();
    await _resumenChanges.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}