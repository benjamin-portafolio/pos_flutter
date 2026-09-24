import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/clientes/cliente_command_service.dart';
import 'package:pos_flutter/application/commands/clientes/crear_cliente_command.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/cliente_event_handler.dart';
import 'package:pos_flutter/application/sync/payloads/cliente_creado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/cliente_actualizado_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_cliente_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/repositories/cliente_repository_impl.dart';
import 'package:pos_flutter/domain/creditos/customer_account.dart';
import 'package:pos_flutter/domain/repositories/confirmed_sale_repository.dart';
import 'package:pos_flutter/domain/repositories/customer_account_repository.dart';
import 'package:pos_flutter/domain/ventas/confirmed_sale.dart';
import 'package:pos_flutter/presentation/pages/gestion_clientes/cliente_account_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_clientes/cliente_form_screen.dart';

class _Account implements CustomerAccountRepository {
  @override
  Stream<CustomerAccount> watchAccount(String id) =>
      Stream.value(CustomerAccount([]));
}

class _Sales implements ConfirmedSaleRepository {
  @override
  Stream<List<ConfirmedSale>> watchSales() => Stream.value(const []);
}

void main() {
  for (final mode in AppMode.values) {
    testWidgets('editar, precargar, guardar y cancelar en ${mode.name}', (
      tester,
    ) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final config = AppConfigController(
        AppConfig.initial.copyWith(mode: mode),
      );
      addTearDown(() => tester.runAsync(db.close));
      addTearDown(config.dispose);
      final projection = DriftClienteProjectionStore(db.clienteDao);
      final handler = ClienteEventHandler(projection);
      final commands = ClienteCommandService(
        clienteProjectionStore: projection,
        commandContext: const LocalCommandContext(
          deviceId: 'tablet',
          userId: 'user',
        ),
        eventStore: DriftLocalEventStore(
          db: db,
          eventDao: db.eventDao,
          eventRefDao: db.eventRefDao,
          appConfigController: config,
          eventProcessor: EventProcessor(
            handlers: {
              ClienteCreadoPayload.eventType: handler.apply,
              ClienteActualizadoPayload.eventType: handler.applyUpdate,
            },
          ),
        ),
      );
      final repository = ClienteRepositoryImpl(db.clienteDao);
      final cliente = await tester.runAsync(() async {
        await commands.crearCliente(
          const CrearClienteCommand(nombre: 'Ana', telefono: '00123'),
        );
        return (await repository.watchClientes().first).single;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ClienteAccountScreen(
            cliente: cliente!,
            repository: _Account(),
            clienteRepository: repository,
            commandService: commands,
            salesRepository: _Sales(),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.text('Editar')).dx, greaterThan(600));
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      expect(find.text('Editar cliente'), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('00123'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Borrar'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const Key('cliente_nombre')),
        'Ana María',
      );
      await tester.enterText(find.byKey(const Key('cliente_telefono')), '');
      await tester.runAsync(() async {
        await tester.tap(find.text('Guardar'));
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pumpAndSettle();
      expect(find.byType(ClienteFormScreen), findsNothing);
      expect(find.text('Ana María'), findsOneWidget);
      expect(find.text('Sin teléfono registrado'), findsOneWidget);
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      expect(find.text('Ana María'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('cliente_nombre')),
        'Cancelar',
      );
      await tester.tap(find.byTooltip('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Ana María'), findsOneWidget);
      await tester.runAsync(() async {
        final rows = await db.select(db.clientes).get();
        expect(rows.single.id, cliente.id);
        expect(rows.single.nombre, 'Ana María');
        expect(await db.select(db.events).get(), hasLength(2));
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  }
}
