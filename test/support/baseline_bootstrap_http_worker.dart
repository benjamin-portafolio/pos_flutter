// Invoked only by the S4 isolated PostgreSQL harness; no production configuration.
import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/commands/creditos/credito_command_service.dart';
import 'package:pos_flutter/application/commands/creditos/registrar_abono_command.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/abono_cliente_event_handler.dart';
import 'package:pos_flutter/application/sync/payloads/abono_cliente_registrado_payload.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_cliente_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_customer_credit_store.dart';
import 'package:pos_flutter/application/commands/inventario/registrar_movimiento_inventario_command.dart';
import 'package:pos_flutter/domain/inventario/tipo_movimiento_inventario.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/proveedores/editar_proveedor_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/recovery/baseline_bootstrap_service.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_synced_event_store.dart';
import 'package:pos_flutter/data/local/recovery/http_baseline_bootstrap_transport.dart';
import 'package:pos_flutter/data/local/recovery/sqlite_baseline_bootstrap_installer.dart';
import 'package:pos_flutter/data/repositories/proveedor_repository_impl.dart';
import 'product_supplier_harness.dart';

void main() {
  test(
    'real HTTP baseline → empty Flutter SQLite → command → push/pull/echo without replay',
    () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      final inputPath = Platform.environment['POS_RECOVERY_S4_BOOTSTRAP'];
      if (inputPath == null || !inputPath.startsWith('/tmp/pos-recovery-s4-')) {
        throw StateError('Explicit isolated S4 input required');
      }
      final input = jsonDecode(await File(inputPath).readAsString()) as Map;
      final uri = Uri.parse(input['url'] as String);
      if (uri.host != '127.0.0.1') {
        throw StateError('Loopback fixture required');
      }
      final dir = await Directory.systemTemp.createTemp(
        'pos-recovery-s4-client-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final transport = HttpBaselineBootstrapTransport(
        baseUri: uri,
        serverInstanceId: input['server_instance_id'] as String,
        generationId: input['generation_id'] as String,
        enrollmentToken: input['token'] as String,
      );
      addTearDown(transport.close);
      final result = await BaselineBootstrapService().installEmpty(
        mode: AppMode.serverSync,
        expectedServer: input['server_instance_id'] as String,
        expectedGeneration: input['generation_id'] as String,
        expectedDigest: input['digest'] as String,
        transport: transport,
        installer: SqliteBaselineBootstrapInstaller(dir),
      );
      final binding = result['binding'] as Map;
      final h = ProductSupplierHarness(
        database: AppDatabase.forTesting(
          NativeDatabase(File(result['database_path'] as String)),
        ),
        mode: AppMode.serverSync,
        context: LocalCommandContext(
          deviceId: binding['device_id'] as String,
          userId: 'fixture-user-C',
        ),
      );
      addTearDown(h.dispose);
      final repo = ProveedorRepositoryImpl(h.db.proveedorDao);
      final base = (await repo.watchProveedores().first).single;
      expect(base.nombre, 'Proveedor acreditado');
      final inventoryId = input['inventory_item_id'] as String?;
      final financial = input['scenario'] == 'financial';
      var processor = h.tracking.processor;
      final beforeEvents = await h.db.select(h.db.events).get();
      expect(
        beforeEvents,
        hasLength(
          financial
              ? 6
              : inventoryId == null
              ? 1
              : 5,
        ),
      );
      expect(
        beforeEvents.every((e) => e.deliveryStatus == 'delivered'),
        isTrue,
      );
      expect(
        await h.db.syncCheckpointDao.obtenerLastFullPullServerSequence(),
        99,
      );
      if (financial) {
        final store = DriftCustomerCreditStore(h.db);
        processor = EventProcessor(
          handlers: {
            AbonoClienteRegistradoPayload.eventType: AbonoClienteEventHandler(
              store,
            ).apply,
          },
        );
        final local = DriftLocalEventStore(
          db: h.db,
          eventDao: h.db.eventDao,
          eventRefDao: h.db.eventRefDao,
          appConfigController: h.tracking.config,
          eventProcessor: processor,
        );
        await CreditoCommandService(
          store: store,
          clientes: DriftClienteProjectionStore(h.db.clienteDao),
          events: local,
          context: h.tracking.context,
        ).registrarAbono(
          RegistrarAbonoCommand(
            id: const Uuid().v4(),
            clienteId: (await h.db.select(h.db.clientes).get()).single.id,
            amountMinor: 300,
            method: 'transfer',
          ),
        );
      } else if (inventoryId == null) {
        await h.supplierCommands.editarProveedor(
          EditarProveedorCommand(
            base: base,
            nombre: 'Proveedor editado desde C',
          ),
        );
      } else {
        final balance =
            (await h.db.select(h.db.inventoryBalances).get()).single;
        expect(balance.quantityOnHandAtomic, 10);
        expect(
          (await h.db.select(h.db.inventoryItems).get()).single.version,
          4,
        );
        await h.tracking.inventoryCommands.registrarMovimiento(
          RegistrarMovimientoInventarioCommand(
            inventoryItemId: inventoryId,
            movementType: TipoMovimientoInventario.stockReceipt,
            quantityDeltaAtomic: 7,
          ),
        );
      }
      final pending = await h.tracking.history.pendingEvents();
      expect(pending, hasLength(1));
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      Future<Map<String, Object?>> request(String path, [Object? body]) async {
        final r = await client.openUrl(
          body == null ? 'GET' : 'POST',
          uri.resolve(path),
        );
        r.headers.set('X-POS-Protocol', '2');
        r.headers.set('X-POS-Server', binding['server_instance_id'] as String);
        r.headers.set('X-POS-Generation', binding['generation_id'] as String);
        r.headers.set('X-POS-Device', binding['device_id'] as String);
        r.headers.set('Authorization', 'Bearer ${binding['token']}');
        if (body != null) {
          r.headers.contentType = ContentType.json;
          r.write(jsonEncode(body));
        }
        final response = await r.close();
        final text = await utf8.decodeStream(response);
        expect(response.statusCode, inInclusiveRange(200, 299));
        return Map<String, Object?>.from(jsonDecode(text) as Map);
      }

      final pushBody = {
        'device_id': binding['device_id'],
        'last_full_pull_server_sequence': 99,
        'last_preflight_server_sequence': 99,
        'events': pending.map((e) => e.toPushJson()).toList(),
      };
      final pushed = await request('/sync/push', pushBody);
      final accepted = (pushed['results'] as List).single as Map;
      expect(accepted['status'], 'accepted');
      expect(accepted['server_sequence'], greaterThan(99));
      expect(
        ((await request('/sync/push', pushBody))['results'] as List)
            .single['status'],
        'duplicate',
      );
      final pull = await request('/sync/pull?since=99');
      final events = (pull['events'] as List)
          .map((e) => SyncEvent.fromJson(Map<String, Object?>.from(e as Map)))
          .toList();
      expect(events, hasLength(1));
      await DriftSyncedEventStore(db: h.db).applySyncedEvents(
        events,
        applyEvent: processor.apply,
        acknowledgeEcho: (e) async {},
        afterApply: () => h.db.syncCheckpointDao
            .actualizarLastFullPullServerSequence(pull['next_cursor'] as int),
      );
      expect(await h.tracking.history.pendingEvents(), isEmpty);
      if (financial) {
        final payments = await h.db.select(h.db.customerPayments).get();
        expect(payments, hasLength(2));
        expect(
          payments.fold<int>(0, (total, row) => total + row.amountMinor),
          500,
        );
        expect(
          (await h.db.select(h.db.accountBalanceBaselines).get())
              .single
              .amountMinor,
          -1000,
        );
      } else if (inventoryId == null) {
        expect(
          (await repo.watchProveedores().first).single.nombre,
          'Proveedor editado desde C',
        );
        expect((await h.db.select(h.db.suppliers).get()).single.version, 2);
        expect(await h.db.select(h.db.inventoryMovements).get(), isEmpty);
      } else {
        expect(
          (await h.db.select(h.db.inventoryBalances).get())
              .single
              .quantityOnHandAtomic,
          17,
        );
        expect(
          (await h.db.select(h.db.inventoryItems).get()).single.version,
          5,
        );
        expect(await h.db.select(h.db.inventoryMovements).get(), hasLength(4));
      }
      expect(
        await h.db.select(h.db.events).get(),
        hasLength(beforeEvents.length + 1),
      );
      expect(await h.db.select(h.db.cashMovements).get(), isEmpty);
    },
  );
}
