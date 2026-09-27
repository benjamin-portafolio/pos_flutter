import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pos_flutter/application/commands/caja/cerrar_caja_command.dart';
import 'package:pos_flutter/data/repositories/cash_repository_impl.dart';
import '../test/support/cash_harness.dart';
import '../test/support/cash_sync_harness.dart';

/// Solo contra servidor dedicado con base temporal vacía. No se ejecuta en suite default.
void main() {
  test(
    'A/B HTTP real: offline, preflight, push causal, duplicate, pull, ecos y solo consulta',
    () async {
      final url = Platform.environment['CASH_E2E_URL'];
      if (url == null) {
        fail('Define CASH_E2E_URL apuntando al servidor de la base temporal.');
      }
      final a = CashHarness(), b = CashHarness(device: 'cash-reader');
      final client = http.Client();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      addTearDown(client.close);
      final sa = CashSyncHarness(a, client, baseUrl: url),
          sb = CashSyncHarness(b, client, baseUrl: url);
      final first = await a.open();
      await a.entry(amount: 8000);
      await a.entry(direction: 'out', amount: 2000);
      await a.entry(method: 'transfer', drawer: false);
      await a.entry(drawer: false);
      final close = await a.cash.cerrar(
        CerrarCajaCommand(
          sessionId: first,
          countedMinor: 15900,
          notes: 'corte offline',
        ),
      );
      final second = await a.open(amount: 500);
      await a.entry(amount: 300);
      for (
        var i = 0;
        i < 8 && (await a.persistence.pendingEvents()).isNotEmpty;
        i++
      ) {
        await sa.preflight.preflightPendingEvents();
        await sa.push.pushPendingEvents();
      }
      expect(await a.persistence.pendingEvents(), isEmpty);
      final e = (await a.persistence.eventById(close))!;
      final response = await client.post(
        Uri.parse('$url/sync/push'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_id': a.context.deviceId,
          'events': [e.toPushJson()],
        }),
      );
      expect(response.statusCode, inInclusiveRange(200, 299));
      final duplicate =
          ((jsonDecode(response.body) as Map)['results'] as List).single as Map;
      expect(duplicate['status'], 'duplicate');
      expect(duplicate['original_sync_status'], 'synced');
      await sa.pull.pullAvailableEvents();
      await sb.pull.pullAvailableEvents();
      final av = await CashRepositoryImpl(a.db).watchSessions().first,
          bv = await CashRepositoryImpl(b.db).watchSessions().first;
      expect(av.length, 2);
      expect(bv.length, 2);
      for (final left in av) {
        final right = bv.singleWhere((s) => s.id == left.id);
        expect(right.status, left.status);
        expect(right.expectedMinor, left.expectedMinor);
        expect(
          right.movements.map((m) => m.id).toSet(),
          left.movements.map((m) => m.id).toSet(),
        );
      }
      expect(
        av.singleWhere((s) => s.id == first).expectedMinor,
        BigInt.from(16000),
      );
      expect(
        av.singleWhere((s) => s.id == first).differenceMinor,
        BigInt.from(-100),
      );
      expect(
        av.singleWhere((s) => s.id == second).expectedMinor,
        BigInt.from(800),
      );
      expect((await a.cashStore.find(first))!.lastEventId, close);
      expect((await a.db.select(a.db.cashMovements).get()).length, 3);
      await expectLater(
        b.cash.cerrar(CerrarCajaCommand(sessionId: second, countedMinor: 800)),
        throwsStateError,
      );
      expect(await b.persistence.lastFullPullServerSequence(), greaterThan(0));
    },
  );
}
