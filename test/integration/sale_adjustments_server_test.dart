import '../support/sale_adjustment_public_http_ui.dart';
import 'package:pos_flutter/application/commands/ventas/conciliar_operacion_venta_command.dart';
import 'package:pos_flutter/application/sync/payloads/operacion_venta_conciliada_payload.dart';
import 'package:flutter/services.dart';
import 'package:pos_flutter/data/local/backup/database_snapshot_service.dart';
import 'package:pos_flutter/data/local/backup/database_restore_service.dart';
import 'package:pos_flutter/data/local/backup/database_state_reader.dart';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/sync/sync_conflict_report_service.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/confirmar_venta_command.dart';
import 'package:pos_flutter/application/commands/ventas/anular_venta_command.dart';
import 'package:pos_flutter/application/commands/ventas/registrar_devolucion_venta_command.dart';
import 'package:pos_flutter/application/commands/caja/abrir_caja_command.dart';
import 'package:pos_flutter/application/commands/caja/cerrar_caja_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/payloads/venta_confirmada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/venta_anulada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/devolucion_venta_registrada_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/sale_adjustment_repository_impl.dart';
import '../support/variant_tracking_harness.dart';
import '../support/sale_adjustment_harness.dart'
    show adjustmentFixtures, object;

const uuid = Uuid();
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final url = Platform.environment['POS_ADJUSTMENTS_SYNC_URL'];
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  testWidgets(
    '3B/4B HTTP/PG: causalidad, incidencia, conciliación, respuesta perdida, corte y replay limpio',
    (tester) async {
      await tester.runAsync(() async {
        // Widget binding supplies path_provider's channel, but this test uses real HTTP.
        final previousHttp = HttpOverrides.current;
        HttpOverrides.global = null;
        addTearDown(() => HttpOverrides.global = previousHttp);
        final dir = await Directory.systemTemp.createTemp(
          'pos-adjustments-http-',
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              (_) async => dir.path,
            );
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('plugins.flutter.io/path_provider'),
                null,
              ),
        );
        final run = uuid.v4();
        VariantTrackingHarness terminal(String letter) =>
            VariantTrackingHarness(
              mode: AppMode.serverSync,
              isolatedSyncHarness: true,
              context: LocalCommandContext(
                deviceId: '$run-$letter',
                userId: 'session3',
              ),
              database: AppDatabase.forTesting(
                NativeDatabase(File('${dir.path}/$letter.sqlite')),
              ),
            );
        var a = terminal('A');
        var b = terminal('B');
        final c = terminal('C');
        final d = terminal('D');
        addTearDown(() async {
          for (final h in [a, b, c, d]) {
            await h.config.dispose();
            await h.db.close();
          }
          await dir.delete(recursive: true);
        });
        Future<void> pushAll(VariantTrackingHarness h) async {
          for (
            var i = 0;
            i < 12 && (await h.history.pendingEvents()).isNotEmpty;
            i++
          ) {
            final report = await h.push(url!).pushPendingEvents();
            expect(report.rejected, 0);
            expect(report.conflicts, 0);
          }
          expect(await h.history.pendingEvents(), isEmpty);
        }

        final ids = await a.create(initial: '10');
        a.config.update(a.config.config.copyWith(cashEnabled: true));
        final sessionA = uuid.v4();
        await a.cash.abrir(
          AbrirCajaCommand(sessionId: sessionA, openingMinor: 1000),
        );
        await a.drafts.agregar(
          AgregarProductoBorradorCommand(variantId: ids.variantId),
        );
        final draft = (await a.db.select(a.db.sales).get()).single;
        final confirmationId = await a.sales.confirmar(
          ConfirmarVentaCommand(
            saleId: draft.id,
            expectedDraftEventId: draft.lastEventId!,
            expectedTotalMinor: draft.totalMinor,
            paymentMethod: 'cash',
            receivedMinor: 1000,
          ),
        );
        final confirmation = (await a.history.eventById(confirmationId))!;
        final original = VentaConfirmadaPayload.fromJson(confirmation.payload);
        Map<String, Object?> adjustment(VariantTrackingHarness h, String kind) {
          final p = object(
            jsonDecode(jsonEncode(adjustmentFixtures().first['payload'])),
          );
          final now = DateTime.now().toUtc().millisecondsSinceEpoch;
          p.addAll({
            'kind': kind,
            'operation_id': uuid.v4(),
            'event_id': uuid.v4(),
            'sale_id': draft.id,
            'confirmation_event_id': confirmationId,
            'expected_revision': 0,
            'previous_adjustment_event_id': null,
            'occurred_at_ms': now,
            'business_date': DateTime.fromMillisecondsSinceEpoch(
              now - 360 * 60000,
              isUtc: true,
            ).toIso8601String().substring(0, 10),
            'total_minor': original.totalMinor,
          });
          final session = h == a ? sessionA : sessionB;
          final opening = h == a ? openingA : openingB;
          p['settlement'] = {
            'method': 'cash',
            'payment_id': original.paymentId,
            'cliente_id': null,
            'action': 'refund_completed',
            'reference': null,
            'cash_enabled': true,
            'cash': {
              'session_id': session,
              'opening_event_id': opening,
              'movement_id': uuid.v4(),
            },
          };
          p['dependency_event_ids'] = [confirmationId, opening];
          p['lines'] = [
            for (final l in original.lines)
              {
                'sale_item_id': l.id,
                'quantity_atomic': l.snapshot.quantity,
                'destination': kind == 'void' ? 'void' : 'restock',
                'reason': null,
                'amount_minor': original.totalMinor,
                'recovered_cost_minor': null,
                'stock': [
                  for (final s in l.consumptions)
                    {
                      'movement_id': uuid.v4(),
                      'original_movement_id': s.movementId,
                      'inventory_item_id': s.inventoryItemId,
                      'quantity_atomic': -s.deltaAtomic,
                    },
                ],
              },
          ];
          return p;
        }

        // Capture against pending confirmation before any HTTP delivery.
        openingA = (await a.cashStore.find(sessionA))!.createdEventId!;
        sessionB = '';
        openingB = '';
        final localA = adjustment(a, 'void');
        await a.adjustments.anular(
          AnularVentaCommand(
            payload: VentaAnuladaPayload.fromJson(localA),
            userId: a.context.userId,
            deviceId: a.context.deviceId,
          ),
        );
        expect(
          (await a.history.eventById(
            localA['event_id'] as String,
          ))!.deliveryStatus,
          'pending',
        );
        expect(
          await a.history.refsForEvents([localA['event_id'] as String]),
          isNotEmpty,
        );
        // Real snapshot/restore before delivery, retaining original identities and refs.
        final snapshot = await DriftDatabaseSnapshotService(
          db: a.db,
          stateReader: DriftDatabaseStateReader(db: a.db),
        ).createSnapshot();
        final captureContext = a.context;
        await DriftDatabaseRestoreService(
          db: a.db,
        ).restoreSnapshot(snapshot.file, sha256: snapshot.sha256);
        await a.config.dispose();
        a = VariantTrackingHarness(
          mode: AppMode.serverSync,
          isolatedSyncHarness: true,
          context: captureContext,
          database: AppDatabase(),
        );
        a.config.update(a.config.config.copyWith(cashEnabled: true));
        await snapshot.file.parent.delete(recursive: true);
        expect(
          (await a.adjustments.recoverIntention(
            localA['operation_id'] as String,
          ))!.eventId,
          localA['event_id'],
        );
        expect(
          (await a.history.eventById(
            localA['event_id'] as String,
          ))!.deliveryStatus,
          'pending',
        );
        expect(
          await a.history.refsForEvents([localA['event_id'] as String]),
          isNotEmpty,
        );
        await a.cash.cerrar(
          CerrarCajaCommand(sessionId: sessionA, countedMinor: 1000),
        );
        // First rounds must not deliver adjustment/cut before confirmation/opening.
        await a.push(url!).pushPendingEvents();
        expect(
          (await a.history.eventById(
            localA['event_id'] as String,
          ))!.deliveryStatus,
          'pending',
        );
        // B obtains only through sale sequence, before A adjustment is accepted.
        for (
          var i = 0;
          i < 5 &&
              (await a.history.eventById(confirmationId))!.deliveryStatus !=
                  'delivered';
          i++
        ) {
          await a.push(url).pushPendingEvents();
        }
        await b.pull(url).pullAvailableEvents(limit: 1);
        b.config.update(b.config.config.copyWith(cashEnabled: true));
        sessionB = uuid.v4();
        await b.cash.abrir(
          AbrirCajaCommand(sessionId: sessionB, openingMinor: 1000),
        );
        openingB = (await b.cashStore.find(sessionB))!.createdEventId!;
        expect((await b.push(url).pushPendingEvents()).synced, 1);
        final localB = adjustment(b, 'return');
        await b.adjustments.devolver(
          RegistrarDevolucionVentaCommand(
            payload: DevolucionVentaRegistradaPayload.fromJson(localB),
            userId: b.context.userId,
            deviceId: b.context.deviceId,
          ),
        );
        await pushAll(a);
        await a.pull(url).pullAvailableEvents(limit: 1);
        final before = await a.adjustmentStore.readDeliveryState();
        await a.history.updateLastFullPullServerSequence(0);
        await a.pull(url).pullAvailableEvents(limit: 2);
        expect(
          (await a.adjustmentStore.readDeliveryState()).inventory,
          before.inventory,
        );
        final event = (await a.history.eventById(
          localA['event_id'] as String,
        ))!;
        expect(
          (await a.db.select(a.db.saleAdjustments).get())
              .single
              .lastServerSequence,
          event.serverSequence,
        );
        // Lost response retry uses original identity and receives original accepted state.
        final response = await http.post(
          Uri.parse('$url/sync/push'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'device_id': a.context.deviceId,
            'events': [event.toPushJson()],
          }),
        );
        expect(
          (jsonDecode(response.body)
              as Map)['results'][0]['original_sync_status'],
          'synced',
        );
        final cursor = await b.history.lastFullPullServerSequence();
        final preflight = await b
            .preflight(url)
            .preflightPendingEvents(maxEvents: 1);
        expect(await b.history.lastFullPullServerSequence(), cursor);
        if (preflight.requiresFullPullBeforePush) {
          await b.pull(url).pullAvailableEvents(limit: 1);
        }
        await b.preflight(url).revalidatePendingEvents();
        expect(
          (await b.history.eventById(
            localB['event_id'] as String,
          ))!.deliveryStatus,
          'conflict',
        );
        final state = await b.adjustmentStore.readDeliveryState();
        expect(state.inventory[ids.resourceId]!.recorded, BigInt.from(11));
        expect(state.inventory[ids.resourceId]!.official, BigInt.from(10));
        expect(state.inventory[ids.resourceId]!.localDifference, BigInt.one);
        expect(state.cash[sessionB]!.recorded, BigInt.zero);
        expect(state.cash[sessionB]!.official, BigInt.from(1000));
        expect((await b.cashStore.current(b.context.deviceId))!.id, sessionB);
        expect(state.incidentEventIds, contains(localB['event_id']));
        final incident =
            (await b.db.select(b.db.saleDeliveryIncidents).get()).single;
        expect(incident.winnerEventId, localA['event_id']);
        final read = (await SaleAdjustmentRepositoryImpl(
          b.db,
        ).watchSales().first).singleWhere((s) => s.original.id == draft.id);
        expect(read.hasIncident, true);
        expect(read.officialRevision, 1);
        final report = await SyncConflictReportService(
          syncPersistence: b.history,
          endpointConfig: SyncEndpointConfig(initialBaseUrl: url),
        ).reportLocalConflicts();
        expect(report.conflicts, 1);
        expect(
          (await b.adjustmentStore.readDeliveryState()).inventory,
          state.inventory,
        );
        // Reopen same file: identities, refs, incident and checkpoint remain.
        await b.config.dispose();
        await b.db.close();
        b = terminal('B');
        expect(
          (await b.adjustmentStore.readDeliveryState()).inventory,
          state.inventory,
        );
        expect(
          await b.history.lastFullPullServerSequence(),
          greaterThanOrEqualTo(cursor),
        );
        expect(
          await b.history.refsForEvents([localB['event_id'] as String]),
          isNotEmpty,
        );
        // Two successive partials captured offline: confirmation -> R1 -> R2 -> cut.
        final nextSession = uuid.v4();
        await a.cash.abrir(
          AbrirCajaCommand(sessionId: nextSession, openingMinor: 0),
        );
        await a.drafts.agregar(
          AgregarProductoBorradorCommand(variantId: ids.variantId),
        );
        await a.drafts.agregar(
          AgregarProductoBorradorCommand(variantId: ids.variantId),
        );
        final nextDraft = (await a.db.select(a.db.sales).get()).singleWhere(
          (s) => s.id != draft.id && s.deviceId == a.context.deviceId,
        );
        final nextConfirmation = await a.sales.confirmar(
          ConfirmarVentaCommand(
            saleId: nextDraft.id,
            expectedDraftEventId: nextDraft.lastEventId!,
            expectedTotalMinor: nextDraft.totalMinor,
            paymentMethod: 'cash',
            receivedMinor: 2000,
          ),
        );
        final nextOriginal = VentaConfirmadaPayload.fromJson(
          (await a.history.eventById(nextConfirmation))!.payload,
        );
        final nextOpening = (await a.cashStore.find(
          nextSession,
        ))!.createdEventId!;
        Map<String, Object?> partial(int revision, String? previous) {
          final p = object(jsonDecode(jsonEncode(localA)));
          final line = nextOriginal.lines.single;
          p.addAll({
            'kind': 'return',
            'operation_id': uuid.v4(),
            'event_id': uuid.v4(),
            'sale_id': nextDraft.id,
            'confirmation_event_id': nextConfirmation,
            'expected_revision': revision,
            'previous_adjustment_event_id': previous,
            'total_minor': 1000,
            'dependency_event_ids': [nextConfirmation, ?previous, nextOpening],
          });
          p['settlement'] = {
            'method': 'cash',
            'payment_id': nextOriginal.paymentId,
            'cliente_id': null,
            'action': 'refund_completed',
            'reference': null,
            'cash_enabled': true,
            'cash': {
              'session_id': nextSession,
              'opening_event_id': nextOpening,
              'movement_id': uuid.v4(),
            },
          };
          p['lines'] = [
            {
              'sale_item_id': line.id,
              'quantity_atomic': 1,
              'destination': 'restock',
              'reason': null,
              'amount_minor': 1000,
              'recovered_cost_minor': null,
              'stock': [
                for (final m in line.consumptions)
                  {
                    'movement_id': uuid.v4(),
                    'original_movement_id': m.movementId,
                    'inventory_item_id': m.inventoryItemId,
                    'quantity_atomic': 1,
                  },
              ],
            },
          ];
          return p;
        }

        final firstPartial = partial(0, null), secondPartial = partial(1, null);
        secondPartial['previous_adjustment_event_id'] =
            firstPartial['event_id'];
        secondPartial['dependency_event_ids'] = [
          nextConfirmation,
          firstPartial['event_id'],
          nextOpening,
        ];
        for (final p in [firstPartial, secondPartial]) {
          await a.adjustments.devolver(
            RegistrarDevolucionVentaCommand(
              payload: DevolucionVentaRegistradaPayload.fromJson(p),
              userId: a.context.userId,
              deviceId: a.context.deviceId,
            ),
          );
        }
        await a.cash.cerrar(
          CerrarCajaCommand(sessionId: nextSession, countedMinor: 0),
        );
        await pushAll(a);
        await a.pull(url).pullAvailableEvents(limit: 1);
        final firstDelivered = (await a.history.eventById(
              firstPartial['event_id'] as String,
            ))!,
            secondDelivered = (await a.history.eventById(
              secondPartial['event_id'] as String,
            ))!;
        expect(
          secondDelivered.baseServerSequence,
          firstDelivered.serverSequence,
        );
        expect((await a.cashStore.find(nextSession))!.status, 'closed');
        final legacy = Platform.environment['POS_ADJUSTMENTS_LEGACY_URL'];
        if (legacy != null) {
          await a.history.updateEventSyncStatus(
            secondDelivered.eventId,
            'pending',
          );
          await expectLater(
            a.push(legacy).pushPendingEvents(),
            throwsA(predicate((e) => e.toString().contains('incompatible'))),
          );
          expect(
            (await a.history.eventById(
              secondDelivered.eventId,
            ))!.deliveryStatus,
            'pending',
          );
          await a.history.updateEventSyncStatus(
            secondDelivered.eventId,
            'delivered',
            serverSequence: secondDelivered.serverSequence,
          );
        }
        await c.pull(url).pullAvailableEvents(limit: 1);
        final clean = await c.adjustmentStore.readDeliveryState();
        expect(clean.inventory[ids.resourceId]!.recorded, BigInt.from(10));
        expect(clean.incidentEventIds, isEmpty);
        expect(
          (await c.db.select(c.db.saleAdjustments).get()).where(
            (d) => d.saleId == draft.id,
          ),
          hasLength(1),
        );
        // 4B: explicit recognition consumes B's preserved physical effects once.
        final details = (await b.reconciliationStore.incident(
          localB['event_id'] as String,
        ))!;
        final now = DateTime.now().toUtc();
        final reconciliation = OperacionVentaConciliadaPayload.fromJson({
          'schema_version': 1,
          'operation_id': uuid.v4(),
          'event_id': uuid.v4(),
          'incident_id': details.id,
          'sale_id': details.saleId,
          'loser_event_id': details.loser.eventId,
          'winner_event_id': details.winnerEventId,
          'official_base_event_id': details.officialBaseEventId,
          'expected_revision': details.officialRevision,
          'occurred_at_ms': now.millisecondsSinceEpoch,
          'utc_offset_minutes': 0,
          'business_date': now.toIso8601String().substring(0, 10),
          'reason':
              'Se reconoce exceso físico conservado en terminal B, sin otra devolución.',
          'preserved_effects': details.evidence.map((e) => e.toJson()).toList(),
          'recovery_effects': [],
        });
        final command = ConciliarOperacionVentaCommand(
          payload: reconciliation,
          userId: b.context.userId,
          deviceId: b.context.deviceId,
        );
        final closedA = jsonEncode(
          (await a.cashStore.find(sessionA))!.close!.toJson(),
        );
        final beforeRecognize = await b.adjustmentStore.readDeliveryState();
        await b.reconciliations.conciliar(command);
        expect(await b.adjustmentStore.hasIncident(draft.id), true);
        expect(
          (await b.adjustmentStore.readDeliveryState())
              .inventory[ids.resourceId]!
              .recorded,
          beforeRecognize.inventory[ids.resourceId]!.recorded,
        );
        final lost = _LosePushResponse();
        await expectLater(
          b.push(url, client: lost).pushPendingEvents(),
          throwsA(anything),
        );
        lost.close();
        expect(
          (await b.history.eventById(reconciliation.eventId))!.deliveryStatus,
          'pending',
        );
        expect(await b.adjustmentStore.hasIncident(draft.id), true);
        expect(
          (await b.adjustmentStore.readDeliveryState())
              .inventory[ids.resourceId]!
              .recorded,
          beforeRecognize.inventory[ids.resourceId]!.recorded,
        );
        await pushAll(b);
        await b.reconciliations.conciliar(command);
        expect(await b.adjustmentStore.hasIncident(draft.id), false);
        final recognized = await b.adjustmentStore.readDeliveryState();
        expect(recognized.inventory[ids.resourceId]!.recorded, BigInt.from(11));
        expect(
          recognized.inventory[ids.resourceId]!.localDifference,
          BigInt.zero,
        );
        expect(recognized.cash[sessionB]!.recorded, BigInt.zero);
        expect(recognized.cash[sessionB]!.localDifference, BigInt.zero);
        await c.pull(url).pullAvailableEvents(limit: 1);
        final recognizedC = await c.adjustmentStore.readDeliveryState();
        expect(
          recognizedC.inventory[ids.resourceId]!.recorded,
          BigInt.from(11),
        );
        expect(recognizedC.cash[sessionB]!.recorded, BigInt.zero);
        final reconciliationEvent = (await b.history.eventById(
          reconciliation.eventId,
        ))!;
        final retry = await http.post(
          Uri.parse('$url/sync/push'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'device_id': b.context.deviceId,
            'events': [reconciliationEvent.toPushJson()],
          }),
        );
        expect(
          (jsonDecode(retry.body) as Map)['results'][0]['original_sync_status'],
          'synced',
        );
        await b.pull(url).pullAvailableEvents(limit: 1);
        await c.pull(url).pullAvailableEvents(limit: 1);
        expect(
          (await c.adjustmentStore.readDeliveryState())
              .inventory[ids.resourceId]!
              .recorded,
          BigInt.from(11),
        );
        expect(
          (await SaleAdjustmentRepositoryImpl(b.db).watchSales().first)
              .singleWhere((s) => s.original.id == draft.id)
              .hasIncident,
          false,
        );
        expect(
          (await c.db.select(c.db.saleAdjustments).get()).where(
            (d) => d.saleId == draft.id,
          ),
          hasLength(1),
        );
        // Un corte nuevo referencia el reconocimiento aceptado; el libro físico
        // perdedor y el corte A anterior conservan sus identidades/evidencia.
        await b.cash.cerrar(
          CerrarCajaCommand(sessionId: sessionB, countedMinor: 0),
        );
        await pushAll(b);
        final cutB = (await b.cashStore.find(sessionB))!.close!;
        expect(cutB.movements.single.eventId, reconciliation.eventId);
        expect(cutB.movements.single.sourceType, 'sale_reconciliation');
        expect(
          (await b.db.select(b.db.cashMovements).get())
              .singleWhere(
                (m) =>
                    m.id ==
                    reconciliation.preservedEffects
                        .singleWhere((e) => e.ledger == 'cash')
                        .effectId,
              )
              .createdEventId,
          localB['event_id'],
        );
        await c.pull(url).pullAvailableEvents(limit: 1);
        await a.pull(url).pullAvailableEvents(limit: 1);
        expect((await c.cashStore.find(sessionB))!.close!.expectedMinor, '0');
        expect(
          jsonEncode((await a.cashStore.find(sessionA))!.close!.toJson()),
          closedA,
        );
        expect(
          (await a.adjustmentStore.readDeliveryState())
              .inventory[ids.resourceId]!
              .recorded,
          BigInt.from(11),
        );
        await b.config.dispose();
        await b.db.close();
        b = terminal('B');
        expect(await b.adjustmentStore.hasIncident(draft.id), false);
        await b.reconciliations.conciliar(command);
        expect(
          (await b.adjustmentStore.readDeliveryState())
              .inventory[ids.resourceId]!
              .localDifference,
          BigInt.zero,
        );
        await d.pull(url).pullAvailableEvents(limit: 1);
        final replay = await d.adjustmentStore.readDeliveryState();
        expect(replay.inventory[ids.resourceId]!.recorded, BigInt.from(11));
        expect(replay.cash[sessionB]!.recorded, BigInt.zero);
        expect((await d.cashStore.find(sessionB))!.close!.expectedMinor, '0');
        expect(replay.incidentEventIds, isEmpty);
        await verifyPublicHttpUi(tester, url, dir);
        await c.pull(url).pullAvailableEvents(limit: 1);
        final beforeUnknown = await c.history.lastFullPullServerSequence();
        await http.post(Uri.parse('$url/test/unknown'));
        await expectLater(
          c.pull(url).pullAvailableEvents(limit: 1),
          throwsUnsupportedError,
        );
        expect(await c.history.lastFullPullServerSequence(), beforeUnknown);
      });
    },
    skip: url == null,
  );
}

// Bindings assigned before capturing either intention; never production globals.
String sessionB = '', openingA = '', openingB = '';

/// HTTP real hasta recibir el commit del servidor; descarta solo su respuesta.
class _LosePushResponse extends http.BaseClient {
  final _inner = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    if (request.url.path.endsWith('/sync/push')) {
      await response.stream.drain<void>();
      throw http.ClientException(
        'Respuesta perdida después del commit',
        request.url,
      );
    }
    return response;
  }

  @override
  void close() => _inner.close();
}
