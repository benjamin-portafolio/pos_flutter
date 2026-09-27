import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_flutter/application/commands/caja/cerrar_caja_command.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/caja_abierta_payload.dart';
import 'package:pos_flutter/application/sync/payloads/caja_cerrada_payload.dart';
import 'package:pos_flutter/data/repositories/cash_repository_impl.dart';
import '../../support/cash_harness.dart';
import '../../support/cash_sync_harness.dart';

void main() {
  late CashHarness h;
  setUp(() => h = CashHarness());
  tearDown(() => h.dispose());
  test(
    'push causal: apertura, operaciones, cierre y nueva apertura en lotes separados',
    () async {
      final a = await h.open();
      await h.entry();
      await h.cash.cerrar(CerrarCajaCommand(sessionId: a, countedMinor: 12500));
      final b = await h.open(amount: 500);
      await h.entry(amount: 300);
      final sent = <List<Map<String, Object?>>>[];
      var sequence = 0;
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        final events = (body['events'] as List)
            .map((e) => Map<String, Object?>.from(e as Map))
            .toList();
        sent.add(events);
        return http.Response(
          jsonEncode({
            'results': [
              for (final e in events)
                {
                  'event_id': e['event_id'],
                  'status': 'accepted',
                  'server_sequence': ++sequence,
                },
            ],
          }),
          200,
        );
      });
      addTearDown(client.close);
      final sync = CashSyncHarness(h, client);
      for (var i = 0; i < 6; i++) {
        await sync.revalidator.revalidatePendingEvents();
        await sync.push.pushPendingEvents();
      }
      final batchByEvent = {
        for (var i = 0; i < sent.length; i++)
          for (final e in sent[i]) e['event_id']: i,
      };
      for (final batch in sent) {
        for (final e in batch) {
          final p = Map<String, Object?>.from(e['payload'] as Map);
          final deps = e['event_type'] == CajaAbiertaPayload.eventType
              ? CajaAbiertaPayload.fromJson(p).dependencyEventIds
              : e['event_type'] == CajaCerradaPayload.eventType
              ? CajaCerradaPayload.fromJson(p).dependencyEventIds
              : p['cash'] is Map
              ? [(p['cash'] as Map)['opening_event_id'] as String]
              : <String>[];
          for (final d in deps) {
            expect(batchByEvent[d]!, lessThan(batchByEvent[e['event_id']]!));
          }
        }
      }
      expect(await h.persistence.pendingEvents(), isEmpty);
      expect((await h.cashStore.find(a))!.status, 'closed');
      expect((await h.cashStore.find(b))!.status, 'open');
    },
  );
  for (final failure in ['conflict', 'rejected']) {
    test(
      'dependencia $failure propaga cierre y siguiente apertura sin borrar dinero',
      () async {
        final id = await h.open();
        final operation = await h.entry();
        final c = await h.cash.cerrar(
          CerrarCajaCommand(sessionId: id, countedMinor: 12500),
        );
        final next = await h.open();
        await h.persistence.updateEventSyncStatus(
          operation,
          failure,
          rejectionReason: 'Incidencia de prueba',
        );
        final client = MockClient((_) async => http.Response('{}', 200));
        addTearDown(client.close);
        await CashSyncHarness(h, client).revalidator.revalidatePendingEvents();
        expect((await h.persistence.eventById(c))!.deliveryStatus, 'conflict');
        expect(
          (await h.persistence.eventById(
            (await h.cashStore.find(next))!.createdEventId!,
          ))!.deliveryStatus,
          'conflict',
        );
        expect((await h.cashStore.find(id))!.status, 'closed');
        expect((await h.cashStore.movements(id)).length, 1);
        final view = (await CashRepositoryImpl(
          h.db,
        ).watchSessions().first).firstWhere((s) => s.id == id);
        expect(view.rejectionReason, isNotNull);
        expect(view.expectedMinor, BigInt.from(12500));
      },
    );
  }
  test(
    'respuesta perdida, duplicate y ecos no reabren ni reaplican importes',
    () async {
      final id = await h.open();
      await h.entry();
      final close = await h.cash.cerrar(
        CerrarCajaCommand(sessionId: id, countedMinor: 12500),
      );
      var lose = true;
      var sequence = 0;
      final accepted = <String, int>{};
      final client = MockClient((request) async {
        final events = (jsonDecode(request.body) as Map)['events'] as List;
        final results = <Object>[];
        for (final raw in events) {
          final e = raw as Map;
          final eid = e['event_id'] as String;
          final duplicate = accepted.containsKey(eid);
          accepted.putIfAbsent(eid, () => ++sequence);
          results.add({
            'event_id': eid,
            'status': duplicate ? 'duplicate' : 'accepted',
            'original_sync_status': 'synced',
            'server_sequence': accepted[eid],
          });
        }
        if (lose) {
          lose = false;
          throw Exception('respuesta perdida');
        }
        return http.Response(jsonEncode({'results': results}), 200);
      });
      addTearDown(client.close);
      final sync = CashSyncHarness(h, client);
      await expectLater(sync.push.pushPendingEvents(), throwsA(anything));
      for (var i = 0; i < 4; i++) {
        await sync.push.pushPendingEvents();
      }
      final originals = <SyncEvent>[];
      for (final e in accepted.entries) {
        originals.add(
          (await h.persistence.eventById(
            e.key,
          ))!.copyWith(serverSequence: e.value, deliveryStatus: 'delivered'),
        );
      }
      originals.sort((a, b) => a.serverSequence!.compareTo(b.serverSequence!));
      await sync.applier.applySyncedEvents(originals);
      await sync.applier.applySyncedEvents(originals);
      expect((await h.cashStore.find(id))!.lastEventId, close);
      expect((await h.cashStore.find(id))!.status, 'closed');
      expect((await h.cashStore.movements(id)).length, 1);
    },
  );
  test('duplicate conflict conserva corte; pending explica espera', () async {
    final id = await h.open();
    await h.cash.cerrar(CerrarCajaCommand(sessionId: id, countedMinor: 10000));
    final client = MockClient((request) async {
      final events = (jsonDecode(request.body) as Map)['events'] as List;
      return http.Response(
        jsonEncode({
          'results': [
            for (final raw in events)
              {
                'event_id': (raw as Map)['event_id'],
                'status': 'duplicate',
                'original_sync_status': 'conflict',
                'server_sequence': 10,
                'reason': 'Apertura en conflicto',
              },
          ],
        }),
        200,
      );
    });
    addTearDown(client.close);
    await CashSyncHarness(h, client).push.pushPendingEvents();
    expect((await h.cashStore.find(id))!.status, 'closed');
    expect(
      (await h.persistence.eventById(
        (await h.cashStore.find(id))!.lastEventId!,
      ))!.deliveryStatus,
      'conflict',
    );
  });
}
