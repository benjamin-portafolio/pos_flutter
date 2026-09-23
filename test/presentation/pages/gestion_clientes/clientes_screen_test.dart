import 'dart:async';
import 'package:pos_flutter/application/sync/projections/cliente_projection_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/clientes/cliente_command_service.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/domain/clientes/cliente.dart';
import 'package:pos_flutter/domain/repositories/cliente_repository.dart';
import 'package:pos_flutter/presentation/pages/gestion_clientes/clientes_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_clientes/cliente_form_screen.dart';

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
}

class _Clients
    implements ClienteRepository, LocalEventStore, ClienteProjectionStore {
  final events = <SyncEvent>[];
  final _changes = StreamController<List<Cliente>>.broadcast();
  final _rows = <Cliente>[];
  @override
  Stream<List<Cliente>> watchClientes() async* {
    yield List.of(_rows);
    yield* _changes.stream;
  }

  @override
  Future<void> appendAndApply(
    SyncEvent event, {
    required List<LocalEventRef> refs,
  }) async {
    events.add(event);
    _rows.add(
      Cliente(
        id: event.aggregateId,
        nombre: event.payload['nombre'] as String,
        telefono: event.payload['telefono'] as String?,
      ),
    );
    _changes.add(List.of(_rows));
  }

  Future<void> close() => _changes.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
