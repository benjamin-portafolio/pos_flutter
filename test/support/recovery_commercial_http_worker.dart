import 'package:pos_flutter/data/repositories/customer_account_repository_impl.dart';
import 'package:pos_flutter/data/repositories/transfer_summary_repository_impl.dart';
import 'package:pos_flutter/data/repositories/account_balance_baseline_repository_impl.dart';
import 'package:pos_flutter/domain/cuenta/saldo_cuenta_estimado.dart';
import 'package:pos_flutter/application/commands/ventas/conciliar_operacion_venta_command.dart';
import 'package:pos_flutter/application/sync/payloads/operacion_venta_conciliada_payload.dart';
// Isolated S4 integration worker, invoked by the PostgreSQL recovery suite.
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/inventario/registrar_movimiento_inventario_command.dart';
import 'package:pos_flutter/application/commands/creditos/credito_command_service.dart';
import 'package:pos_flutter/application/commands/creditos/registrar_abono_command.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/confirmar_venta_command.dart';
import 'package:pos_flutter/application/commands/ventas/registrar_devolucion_venta_command.dart';
import 'package:pos_flutter/application/recovery/baseline_bootstrap_service.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/abono_cliente_event_handler.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/devolucion_venta_registrada_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_cliente_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_customer_credit_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_synced_event_store.dart';
import 'package:pos_flutter/data/local/recovery/http_baseline_bootstrap_transport.dart';
import 'package:pos_flutter/data/local/recovery/sqlite_baseline_bootstrap_installer.dart';
import 'package:pos_flutter/domain/inventario/tipo_movimiento_inventario.dart';
import 'variant_tracking_harness.dart';
import 'package:http/http.dart' as http;
import 'package:pos_flutter/application/sync/exceptions/sync_push_exception.dart';
import 'package:pos_flutter/data/local/sync/guarded_sync_client.dart';
import 'package:pos_flutter/application/sync/sync_network_gate.dart';
import 'package:pos_flutter/application/sync/sync_installation.dart';
import 'package:pos_flutter/application/sync/server_echo_acknowledger.dart';
import 'package:pos_flutter/data/local/drift/drift_confirmed_sale_store.dart';
import 'package:pos_flutter/application/recovery/recovery_cancellation.dart';
import 'package:pos_flutter/application/recovery/recovery_diagnostic.dart';
import 'package:pos_flutter/application/recovery/recovery_package_service.dart';
import 'package:pos_flutter/application/recovery/recovery_package_reader.dart';
import 'package:pos_flutter/data/local/recovery/drift_recovery_snapshot_source.dart';
import 'package:pos_flutter/application/commands/caja/abrir_caja_command.dart';

void main() {
  test(
    'commercial HTTP bootstrap and new sale, payment, return, stock with duplicate delivery',
    () async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      final inputPath = Platform.environment['POS_RECOVERY_S4_BOOTSTRAP']!;
      if (!inputPath.startsWith('/tmp/pos-recovery-s4-')) {
        throw StateError('Isolated fixture required');
      }
      final input = jsonDecode(await File(inputPath).readAsString()) as Map;
      final uri = Uri.parse(input['url'] as String);
      if (uri.host != '127.0.0.1') throw StateError('Loopback required');
      final dir = await Directory.systemTemp.createTemp(
        'pos-recovery-s4-commercial-',
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
      final binding = result['binding'] as Map, ids = input['ids'] as Map;
      final context = LocalCommandContext(
        deviceId: binding['device_id'] as String,
        userId: 'commercial-user-C',
      );
      final h = VariantTrackingHarness(
        database: AppDatabase.forTesting(
          NativeDatabase(File(result['database_path'] as String)),
        ),
        mode: AppMode.serverSync,
        context: context,
        isolatedSyncHarness: true,
      );
      addTearDown(h.db.close);
      final frontier = int.parse(input['h'] as String);
      final baselineAdjustments=(input['counts'] as Map)['sale_adjustments'] as int;
      expect(
        await h.db.syncCheckpointDao.obtenerLastFullPullServerSequence(),
        frontier,
      );
      expect(await h.db.select(h.db.sales).get(), hasLength(5));
      expect(await h.db.select(h.db.saleAdjustments).get(), hasLength(baselineAdjustments));
      expect(await h.db.select(h.db.cashSessions).get(), hasLength(1));
      expect(
        (await h.db.select(h.db.cashSessions).get()).single.status,
        'closed',
      );
      expect(await h.history.pendingEvents(), isEmpty);
      final bank=(await AccountBalanceBaselineRepositoryImpl(h.db).watchBaseline().first)!;
      final transfers=TransferSummaryRepositoryImpl(h.db);
      final initialTransfers=await transfers.watchTransferSummary(fromMs:0,toMs:9007199254740991).first;
      expect(SaldoCuentaEstimado.fromMovements(baseline:bank,movements:initialTransfers.movements).estimatedMinor,BigInt.from(-1200));
      expect((await CustomerAccountRepositoryImpl(h.db).watchAccount(ids['customer'] as String).first).balanceMinor,BigInt.from(300));
      expect((await h.db.select(h.db.cashSessions).get()).single.expectedMinor,'250');
      final resource = ids['resource'] as String;
      final beforeStock = (await h.db.select(h.db.inventoryBalances).get())
          .firstWhere((b) => b.inventoryItemId == resource)
          .quantityOnHandAtomic;
      await h.inventoryCommands.registrarMovimiento(
        RegistrarMovimientoInventarioCommand(
          inventoryItemId: resource,
          movementType: TipoMovimientoInventario.stockReceipt,
          quantityDeltaAtomic: 7,
        ),
      );
      final credit = DriftCustomerCreditStore(h.db),
          abonoHandler = AbonoClienteEventHandler(
            DriftCustomerCreditStore(h.db),
          );
      final processor = EventProcessor(
        handlers: {
          'abono_cliente_registrado': abonoHandler.apply,
          for (final type in [
            'caja_abierta',
            'venta_confirmada',
            'devolucion_venta_registrada',
            'operacion_venta_conciliada',
            'movimiento_inventario_registrado',
          ])
            type: h.processor.apply,
        },
      );
      final local = DriftLocalEventStore(
        db: h.db,
        eventDao: h.db.eventDao,
        eventRefDao: h.db.eventRefDao,
        appConfigController: h.config,
        eventProcessor: processor,
      );
      await CreditoCommandService(
        store: credit,
        clientes: DriftClienteProjectionStore(h.db.clienteDao),
        events: local,
        context: context,
      ).registrarAbono(
        RegistrarAbonoCommand(
          id: const Uuid().v4(),
          clienteId: ids['customer'] as String,
          amountMinor: 300,
          method: 'transfer',
        ),
      );
      await h.drafts.agregar(
        AgregarProductoBorradorCommand(variantId: ids['variant'] as String),
      );
      final draft = (await h.db.saleDao.findDraft(
        context.userId,
        context.deviceId,
      ))!;
      await h.sales.confirmar(
        ConfirmarVentaCommand(
          saleId: draft.id,
          expectedDraftEventId: draft.lastEventId!,
          expectedTotalMinor: draft.totalMinor,
          paymentMethod: 'transfer',
        ),
      );
      final ownSession = const Uuid().v4();
      await h.cash.abrir(
        AbrirCajaCommand(sessionId: ownSession, openingMinor: 100),
      );
      final old = (await h.db.select(h.db.events).get()).firstWhere(
        (e) =>
            e.eventType == 'devolucion_venta_registrada' &&
            e.aggregateId == ids['measuredSale'],
      );
      final p = Map<String, Object?>.from(jsonDecode(old.payload) as Map);
      final previousEvent = p['event_id'];
      p['operation_id'] = const Uuid().v4();
      p['event_id'] = const Uuid().v4();
      p['expected_revision'] = 1;
      p['previous_adjustment_event_id'] = previousEvent;
      p['total_minor'] = 34;
      final now = DateTime.now().toUtc();
      p['occurred_at_ms'] = now.millisecondsSinceEpoch;
      p['business_date'] = now.toIso8601String().substring(0, 10);
      final line = Map<String, Object?>.from(
        (p['lines'] as List).single as Map,
      );
      line['amount_minor'] = 34;
      line['recovered_cost_minor'] = 16;
      final stock = Map<String, Object?>.from(
        (line['stock'] as List).single as Map,
      );
      stock['movement_id'] = const Uuid().v4();
      line['stock'] = [stock];
      p['lines'] = [line];
      final cash = (await h.cash.binding(method: 'cash', amountMinor: 34))!;
      final settlement = Map<String, Object?>.from(p['settlement'] as Map);
      settlement['cash_enabled'] = true;
      settlement['cash'] = cash.toJson();
      p['settlement'] = settlement;
      p['dependency_event_ids'] = [
        p['confirmation_event_id'],
        previousEvent,
        cash.openingEventId,
      ];
      await h.adjustments.devolver(
        RegistrarDevolucionVentaCommand(
          payload: DevolucionVentaRegistradaPayload.fromJson(p),
          userId: context.userId,
          deviceId: context.deviceId,
        ),
      );
      final pending = await h.history.pendingEvents();
      expect(pending, hasLength(5));
      // An incompatible/old-generation terminal keeps its original pending
      // intentions and physical projection after the actual push service fails.
      final pendingBefore = pending.map((e) => e.toPushJson()).toList();
      final legacy = http.Client();
      addTearDown(legacy.close);
      await expectLater(
        h.push(uri.toString(), client: legacy).pushPendingEvents(),
        throwsA(isA<SyncPushException>()),
      );
      expect(
        (await h.history.pendingEvents()).map((e) => e.toPushJson()).toList(),
        pendingBefore,
      );
      final stale = GuardedSyncClient(
        SyncNetworkGate(isServerSync: () => true),
        http.Client(),
        installation: SyncInstallation({
          'phase': 'active',
          'endpoint': uri.toString(),
          'binding': {...binding, 'generation_id': const Uuid().v4()},
        }, persist: (_) async {}),
      );
      addTearDown(stale.close);
      await expectLater(
        h.push(uri.toString(), client: stale).pushPendingEvents(),
        throwsA(isA<SyncPushException>()),
      );
      expect(
        (await h.history.pendingEvents()).map((e) => e.toPushJson()).toList(),
        pendingBefore,
      );
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      Future<Map<String, Object?>> request(String path, [Object? body]) async {
        final req = await client.openUrl(
          body == null ? 'GET' : 'POST',
          uri.resolve(path),
        );
        for (final e in {
          'X-POS-Protocol': '2',
          'X-POS-Server': binding['server_instance_id'],
          'X-POS-Generation': binding['generation_id'],
          'X-POS-Device': binding['device_id'],
          'Authorization': 'Bearer ${binding['token']}',
        }.entries) {
          req.headers.set(e.key, e.value!);
        }
        if (body != null) {
          req.headers.contentType = ContentType.json;
          req.write(jsonEncode(body));
        }
        final res = await req.close(), text = await utf8.decodeStream(res);
        expect(res.statusCode, inInclusiveRange(200, 299), reason: text);
        return Map<String, Object?>.from(jsonDecode(text) as Map);
      }

      final push = {
        'device_id': binding['device_id'],
        'last_full_pull_server_sequence': frontier,
        'last_preflight_server_sequence': frontier,
        'events': pending.map((e) => e.toPushJson()).toList(),
      };
      final response = await request('/sync/push', push);
      expect(
        (response['results'] as List).map((e) => e['status']),
        everyElement('accepted'),
        reason: jsonEncode(response),
      );
      expect(
        ((await request('/sync/push', push))['results'] as List).map(
          (e) => e['status'],
        ),
        everyElement('duplicate'),
      );
      final pulled = await request('/sync/pull?since=$frontier');
      final events = (pulled['events'] as List)
          .map((e) => SyncEvent.fromJson(Map<String, Object?>.from(e as Map)))
          .toList();
      expect(events, hasLength(5));
      final echo = ServerEchoAcknowledger(
        categoriaProjectionStore: h.categories,
        inventoryProjectionStore: h.inventory,
        productoProjectionStore: h.products,
        confirmedSaleStore: DriftConfirmedSaleStore(h.db),
        customerCreditStore: credit,
        cashProjectionStore: h.cashStore,
        saleAdjustmentStore: h.adjustmentStore,
        saleReconciliationStore: h.reconciliationStore,
      );
      final store = DriftSyncedEventStore(db: h.db);
      for (var attempt = 0; attempt < 2; attempt++) {
        await store.applySyncedEvents(
          events,
          applyEvent: processor.apply,
          acknowledgeEcho: echo.acknowledge,
          afterApply: () =>
              h.db.syncCheckpointDao.actualizarLastFullPullServerSequence(
                pulled['next_cursor'] as int,
              ),
        );
      }
      expect(await h.history.pendingEvents(), isEmpty);
      expect(
        (await h.db.select(h.db.inventoryBalances).get())
            .firstWhere((b) => b.inventoryItemId == resource)
            .quantityOnHandAtomic,
        beforeStock + 6,
      );
      expect(await h.db.select(h.db.sales).get(), hasLength(6));
      expect(await h.db.select(h.db.customerPayments).get(), hasLength(2));
      expect(await h.db.select(h.db.saleAdjustments).get(), hasLength(baselineAdjustments+1));
      // An admissible ORIGINAL physical losing branch, authored by the real
      // Flutter command before an independently accepted competing return.
      final oldCredit=(await h.db.select(h.db.events).get()).firstWhere((e)=>e.eventType=='devolucion_venta_registrada'&&e.aggregateId==ids['creditSale']&&e.deliveryStatus=='delivered');
      final losing=Map<String,Object?>.from(jsonDecode(oldCredit.payload) as Map);
      (losing['settlement'] as Map)['cash_enabled']=true;
      losing['operation_id']=const Uuid().v4();losing['event_id']=const Uuid().v4();losing['expected_revision']=1;losing['previous_adjustment_event_id']=oldCredit.eventId;
      final lossTime=DateTime.now().toUtc();losing['occurred_at_ms']=lossTime.millisecondsSinceEpoch;losing['business_date']=lossTime.toIso8601String().substring(0,10);losing['dependency_event_ids']=[losing['confirmation_event_id'],oldCredit.eventId];
      final losingLine=Map<String,Object?>.from((losing['lines'] as List).single as Map),losingStock=Map<String,Object?>.from((((losing['lines'] as List).single as Map)['stock'] as List).single as Map);losingStock['movement_id']=const Uuid().v4();losingLine['stock']=[losingStock];losing['lines']=[losingLine];
      await h.adjustments.devolver(RegistrarDevolucionVentaCommand(payload:DevolucionVentaRegistradaPayload.fromJson(losing),userId:context.userId,deviceId:context.deviceId));
      final opponentTransport=HttpBaselineBootstrapTransport(baseUri:uri,serverInstanceId:input['server_instance_id'] as String,generationId:input['generation_id'] as String,enrollmentToken:input['opponent_token'] as String);addTearDown(opponentTransport.close);
      final opponentResult=await BaselineBootstrapService().installEmpty(mode:AppMode.serverSync,expectedServer:input['server_instance_id'] as String,expectedGeneration:input['generation_id'] as String,expectedDigest:input['digest'] as String,transport:opponentTransport,installer:SqliteBaselineBootstrapInstaller(Directory('${dir.path}/opponent')));
      final opponent=Map<String,Object?>.from(opponentResult['binding'] as Map),winning=Map<String,Object?>.from(jsonDecode(jsonEncode(losing)) as Map);
      winning['operation_id']=const Uuid().v4();winning['event_id']=const Uuid().v4();(((winning['lines'] as List).single as Map)['stock'] as List).single['movement_id']=const Uuid().v4();
      final winnerRequest=await client.postUrl(uri.resolve('/sync/push'));
      for(final entry in {'X-POS-Protocol':'2','X-POS-Server':opponent['server_instance_id'],'X-POS-Generation':opponent['generation_id'],'X-POS-Device':opponent['device_id'],'Authorization':'Bearer ${opponent['token']}'}.entries){winnerRequest.headers.set(entry.key,entry.value!);}
      winnerRequest.headers.contentType=ContentType.json;winnerRequest.write(jsonEncode({'device_id':opponent['device_id'],'last_full_pull_server_sequence':frontier,'last_preflight_server_sequence':frontier,'events':[{'event_id':winning['event_id'],'aggregate_type':'sale','aggregate_id':ids['creditSale'],'event_type':'devolucion_venta_registrada','device_id':opponent['device_id'],'user_id':'fixture-opponent','local_sequence':1,'created_at_local':lossTime.toIso8601String(),'base_version':2,'base_server_sequence':oldCredit.serverSequence,'payload':winning}]}));
      final winnerResponse=await winnerRequest.close(),winnerText=await utf8.decodeStream(winnerResponse);expect(winnerResponse.statusCode,inInclusiveRange(200,299),reason:winnerText);expect(((jsonDecode(winnerText) as Map)['results'] as List).single['status'],'accepted');
      final boundClient=GuardedSyncClient(SyncNetworkGate(isServerSync:()=>true),http.Client(),installation:SyncInstallation({'phase':'active','endpoint':uri.toString(),'binding':binding},persist:(_)async{}));addTearDown(boundClient.close);
      final conflict=await h.push(uri.toString(),client:boundClient).pushPendingEvents();expect(conflict.conflicts,1);
      final wonPull=await request('/sync/pull?since=${pulled['next_cursor']}');
      await store.applySyncedEvents((wonPull['events'] as List).map((e)=>SyncEvent.fromJson(Map<String,Object?>.from(e as Map))).toList(),applyEvent:processor.apply,acknowledgeEcho:echo.acknowledge,afterApply:()=>h.db.syncCheckpointDao.actualizarLastFullPullServerSequence(wonPull['next_cursor'] as int));
      final incident=(await h.reconciliationStore.incident(losing['event_id'] as String))!;
      final resolvedAt=DateTime.now().toUtc();
      final resolution=OperacionVentaConciliadaPayload.fromJson({'schema_version':1,'operation_id':const Uuid().v4(),'event_id':const Uuid().v4(),'incident_id':incident.id,'sale_id':incident.saleId,'loser_event_id':incident.loser.eventId,'winner_event_id':incident.winnerEventId,'official_base_event_id':incident.officialBaseEventId,'expected_revision':incident.officialRevision,'occurred_at_ms':resolvedAt.millisecondsSinceEpoch,'utc_offset_minutes':0,'business_date':resolvedAt.toIso8601String().substring(0,10),'reason':'Evidencia original conservada y exceso recuperado','preserved_effects':incident.evidence.map((e)=>e.toJson()).toList(),'recovery_effects':incident.evidence.map((e)=>{...e.toJson(),'effect_id':const Uuid().v4(),'delta':-e.delta,'occurred_at_ms':resolvedAt.millisecondsSinceEpoch,'business_date':resolvedAt.toIso8601String().substring(0,10)}).toList()});
      await h.reconciliations.conciliar(ConciliarOperacionVentaCommand(payload:resolution,userId:context.userId,deviceId:context.deviceId));
      final resolved=await h.push(uri.toString(),client:boundClient).pushPendingEvents();expect(resolved.synced,1);
      final resolutionPull=await request('/sync/pull?since=${wonPull['next_cursor']}');
      await store.applySyncedEvents((resolutionPull['events'] as List).map((e)=>SyncEvent.fromJson(Map<String,Object?>.from(e as Map))).toList(),applyEvent:processor.apply,acknowledgeEcho:echo.acknowledge,afterApply:()=>h.db.syncCheckpointDao.actualizarLastFullPullServerSequence(resolutionPull['next_cursor'] as int));
      expect(await h.history.pendingEvents(),isEmpty);expect((await h.db.select(h.db.saleDeliveryIncidents).get()).single.resolutionEventId,resolution.eventId);
      final currentTransfers=await transfers.watchTransferSummary(fromMs:0,toMs:9007199254740991).first;
      expect(SaldoCuentaEstimado.fromMovements(baseline:bank,movements:currentTransfers.movements).estimatedMinor,BigInt.from(-400));
      expect((await CustomerAccountRepositoryImpl(h.db).watchAccount(ids['customer'] as String).first).balanceMinor,BigInt.from(1100));
      final exportRoot = Directory('${File(inputPath).parent.path}/roundtrip');
      final cancellation = RecoveryCancellation();
      final snapshot = await DriftRecoverySnapshotSource(h.db).capture(
        privateDirectory: exportRoot,
        mode: AppMode.serverSync,
        deviceId: context.deviceId,
        appRevision: 'isolated-commercial-roundtrip',
        cancellation: cancellation,
      );
      try {
        final diagnostic = await RecoveryDiagnostic.inspect(
          snapshot,
          cancellation,
        );
        expect(
          diagnostic.admissible,
          isTrue,
          reason: jsonEncode(diagnostic.toJson()),
        );
        final package = await RecoveryPackageService().generate(
          snapshot,
          privateDirectory: exportRoot,
          cancellation: cancellation,
        );
        await File(
          '${File(inputPath).parent.path}/roundtrip-path.txt',
        ).writeAsString(package.path);
        await File(
          '${File(inputPath).parent.path}/source-prepared.json',
        ).writeAsString(
          jsonEncode({
            'cut': snapshot.cut,
            'snapshot_path': snapshot.file.path,
            'package_id': snapshot.cut['package_id'],
            'package_path': package.path,
            'manifest_digest': await RecoveryPackageReader().verify(
              package,
              cancellation,
            ),
          }),
        );
      } finally {
        snapshot.close();
      }
      expect(
        (await h.db.select(h.db.saleAdjustments).get())
            .where((a) => a.saleId == ids['measuredSale'])
            .fold(0, (int n, a) => n + a.amountMinor),
        67,
      );
    },
  );
}
