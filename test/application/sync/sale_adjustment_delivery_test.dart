import 'package:pos_flutter/application/commands/caja/cerrar_caja_command.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/commands/ventas/sale_adjustment_command_service.dart';
import 'package:pos_flutter/application/sync/handlers/sale_adjustment_event_handler.dart';
import 'package:pos_flutter/application/sync/models/sale_adjustment_outcome.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_push_service.dart';
import '../../support/sale_adjustment_harness.dart';
import '../../support/variant_tracking_harness.dart';

void main() {
  for (final outcome in [
    'accepted',
    'pending',
    'conflict',
    'rejected',
    'duplicate:synced',
    'duplicate:conflict',
    'duplicate:rejected',
    'duplicate:pending',
    'incompatible:adjustments',
    'incompatible:reconciliation',
  ]) {
    test(
      '3B $outcome conserva documento/stock/caja y respeta resultado original',
      () async {
        final h = await SaleAdjustmentHarness.create();
        h.config.update(h.config.config.copyWith(mode: AppMode.serverSync));
        final f = adjustmentFixtures().first;
        await h.seed(f);
        final sync = VariantTrackingHarness(
          database: h.db,
          mode: AppMode.serverSync,
          context: h.context,
          isolatedSyncHarness: true,
        );
        addTearDown(() async {
          await sync.config.dispose();
          await h.config.dispose();
          await h.db.close();
          await h.directory.delete(recursive: true);
        });
        var sequence = 0, posts = 0;
        for (final e in await h.db.select(h.db.events).get()) {
          await sync.history.updateEventSyncStatus(
            e.eventId,
            'delivered',
            serverSequence: ++sequence,
          );
        }
        final handler = SaleAdjustmentEventHandler(
          store: h.store,
          cash: h.cashStore,
          config: h.config,
          isolatedSyncHarness: true,
        );
        final commands = SaleAdjustmentCommandService(
          store: h.store,
          events: h.events(handler.apply),
          config: h.config,
          context: h.context,
          isolatedSyncHarness: true,
        );
        final p = object(f['payload']);
        await h.execute(p, commands: commands);
        final before = await h.store.readDeliveryState();
        final client = MockClient((request) async {
          if (request.url.path == '/sync/health') {
            return http.Response(
              jsonEncode({
                'status': 'ok',
                'capabilities': [
                  if (outcome != 'incompatible:adjustments')
                    'sale_adjustments_v1',
                  if (outcome != 'incompatible:reconciliation')
                    'sale_reconciliations_v1',
                ],
                'latest_server_sequence': sequence,
                'server_time': DateTime.now().toIso8601String(),
              }),
              200,
            );
          }
          posts++;
          final e =
              ((jsonDecode(request.body) as Map)['events'] as List).single;
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'event_id': e['event_id'],
                  'status': outcome.split(':').first,
                  'original_sync_status': outcome.contains(':')
                      ? outcome.split(':').last
                      : null,
                  'server_sequence': 100,
                  'created_at_server': DateTime.now().toIso8601String(),
                },
              ],
            }),
            200,
          );
        });
        addTearDown(client.close);
        final push = SyncPushService(
          syncPersistence: sync.history,
          endpointConfig: SyncEndpointConfig(initialBaseUrl: 'http://test'),
          conflictProjectionCleaner: sync.cleaner,
          client: client,
        );
        if (outcome.startsWith('incompatible:')) {
          await expectLater(
            push.pushPendingEvents(),
            throwsA(predicate((e) => e.toString().contains('incompatible'))),
          );
          expect(posts, 0);
          expect(
            (await sync.history.eventById(
              p['event_id'] as String,
            ))!.deliveryStatus,
            'pending',
          );
          expect(
            (await h.store.readDeliveryState()).inventory,
            before.inventory,
          );
          expect((await h.store.readDeliveryState()).cash, before.cash);
          return;
        }
        await push.pushPendingEvents();
        final expected = switch (outcome) {
          'accepted' || 'duplicate:synced' => 'delivered',
          'duplicate:conflict' => 'conflict',
          'duplicate:rejected' => 'rejected',
          'duplicate:pending' => 'pending',
          _ => outcome,
        };
        expect(
          (await sync.history.eventById(
            p['event_id'] as String,
          ))!.deliveryStatus,
          expected,
        );
        final after = await h.store.readDeliveryState();
        expect(
          after.inventory.map((k, v) => MapEntry(k, v.recorded)),
          before.inventory.map((k, v) => MapEntry(k, v.recorded)),
        );
        expect(
          after.cash.map((k, v) => MapEntry(k, v.recorded)),
          before.cash.map((k, v) => MapEntry(k, v.recorded)),
        );
        expect(await h.db.select(h.db.saleAdjustments).get(), hasLength(1));
        expect(
          await h.store.hasIncident(p['sale_id'] as String),
          ['conflict', 'rejected'].contains(expected),
        );
        final duplicate = await h.execute(p, commands: commands);
        expect(duplicate.status, SaleAdjustmentOutcomeStatus.duplicate);
        expect(duplicate.originalStatus, switch (expected) {
          'pending' => SaleAdjustmentOutcomeStatus.pending,
          'conflict' => SaleAdjustmentOutcomeStatus.conflict,
          'rejected' => SaleAdjustmentOutcomeStatus.rejected,
          _ => SaleAdjustmentOutcomeStatus.accepted,
        });
      },
    );
  }
  for (final missing in [true, false]) {
    test(
      'S08 dependencia ${missing ? 'ausente' : 'terminal'}: espera o propaga al corte sin deshacer hechos',
      () async {
        final h = await SaleAdjustmentHarness.create();
        h.config.update(h.config.config.copyWith(mode: AppMode.serverSync));
        final fixture = adjustmentFixtures().first;
        await h.seed(fixture);
        final sync = VariantTrackingHarness(
          database: h.db,
          mode: AppMode.serverSync,
          context: h.context,
          isolatedSyncHarness: true,
        );
        addTearDown(() async {
          await sync.config.dispose();
          await h.config.dispose();
          await h.db.close();
          await h.directory.delete(recursive: true);
        });
        var sequence = 0;
        for (final e in await h.db.select(h.db.events).get()) {
          await sync.history.updateEventSyncStatus(
            e.eventId,
            'delivered',
            serverSequence: ++sequence,
          );
        }
        final p = object(jsonDecode(jsonEncode(fixture['payload'])));
        if (missing) {
          p['dependency_event_ids'] = [
            ...(p['dependency_event_ids'] as List),
            '00000000-0000-4000-8000-000000009999',
          ];
        }
        final handler = SaleAdjustmentEventHandler(
          store: h.store,
          cash: h.cashStore,
          config: h.config,
          isolatedSyncHarness: true,
        );
        final commands = SaleAdjustmentCommandService(
          store: h.store,
          events: h.events(handler.apply),
          config: h.config,
          context: h.context,
          isolatedSyncHarness: true,
        );
        await h.execute(p, commands: commands);
        final session =
            (object(p['settlement'])['cash'] as Map)['session_id'] as String;
        sync.config.update(h.config.config);
        final close = await sync.cash.cerrar(
          CerrarCajaCommand(sessionId: session, countedMinor: 0),
        );
        if (!missing) {
          await sync.history.updateEventSyncStatus(
            p['confirmation_event_id'] as String,
            'rejected',
          );
        }
        final before = await h.store.readDeliveryState();
        final client = MockClient(
          (r) async => throw StateError('No debe enviar dependientes.'),
        );
        addTearDown(client.close);
        final report = await SyncPushService(
          syncPersistence: sync.history,
          endpointConfig: SyncEndpointConfig(initialBaseUrl: 'http://test'),
          conflictProjectionCleaner: sync.cleaner,
          client: client,
        ).pushPendingEvents();
        expect(missing ? report.pending : report.conflicts, 2);
        expect(
          (await sync.history.eventById(close))!.deliveryStatus,
          missing ? 'pending' : 'conflict',
        );
        expect(
          (await h.store.readDeliveryState()).inventory.map(
            (k, v) => MapEntry(k, v.recorded),
          ),
          before.inventory.map((k, v) => MapEntry(k, v.recorded)),
        );
        if (!missing) {
          expect(
            (await h.db.select(h.db.saleDeliveryIncidents).get())
                .single
                .blockedByEventId,
            p['confirmation_event_id'],
          );
        }
      },
    );
  }
}
