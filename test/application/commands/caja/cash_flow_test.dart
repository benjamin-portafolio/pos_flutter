import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/commands/caja/abrir_caja_command.dart';
import 'package:pos_flutter/application/commands/caja/cerrar_caja_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/payloads/caja_cerrada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/caja_abierta_payload.dart';
import 'package:pos_flutter/application/sync/payloads/cash_binding_payload.dart';
import 'package:pos_flutter/application/sync/payloads/movimiento_financiero_registrado_payload.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import '../../../support/cash_harness.dart';

void main() {
  late CashHarness h;
  setUp(() => h = CashHarness());
  tearDown(() => h.dispose());
  test('fixtures compartidos: contrato, acumulación y total corrupto', () {
    final root =
        Platform.environment['CASH_FIXTURES_DIR'] ??
        '/Users/benjamin/Library/CloudStorage/GoogleDrive-benjamin94833@gmail.com/My Drive/Projects/POS/analisis /08 - Roadmap/Caja/Fixtures';
    Map<String, Object?> read(String f) => Map<String, Object?>.from(
      jsonDecode(File('$root/$f.json').readAsStringSync()) as Map,
    );
    expect(CajaAbiertaPayload.fromJson(read('open-valid')).openingMinor, 10000);
    final c = CajaCerradaPayload.fromJson(read('close-valid'));
    c.verify(10000, c.movements);
    final bad = CajaCerradaPayload.fromJson(read('close-wrong-total'));
    expect(() => bad.verify(10000, bad.movements), throwsStateError);
    expect(
      CashBindingPayload.optional(read('cash-binding'), 'cash', 1),
      isNotNull,
    );
    expect(
      () => CashBindingPayload.optional(read('cash-binding'), 'transfer', 1),
      throwsFormatException,
    );
  });
  test('apertura duplicada, una abierta y reintento de cierre', () async {
    final id = await h.open();
    final first = (await h.cashStore.find(id))!.createdEventId;
    expect(
      await h.cash.abrir(AbrirCajaCommand(sessionId: id, openingMinor: 10000)),
      first,
    );
    await expectLater(h.open(), throwsStateError);
    final c = CerrarCajaCommand(
      sessionId: id,
      countedMinor: 10000,
      notes: '  corte  ',
    );
    final close = await h.cash.cerrar(c);
    expect(await h.cash.cerrar(c), close);
    await expectLater(
      h.cash.cerrar(CerrarCajaCommand(sessionId: id, countedMinor: 0)),
      throwsStateError,
    );
    expect((await h.db.select(h.db.events).get()).length, 2);
  });
  test(
    'ingreso/gasto explícitos, transfer y cash fuera del cajón excluidos',
    () async {
      final id = await h.open();
      await h.entry(amount: 4000);
      await h.entry(direction: 'out', amount: 1000);
      await h.entry(method: 'transfer', drawer: false);
      await h.entry(drawer: false);
      final movements = await h.cashStore.movements(id);
      expect(movements.length, 2);
      await h.cash.cerrar(
        CerrarCajaCommand(sessionId: id, countedMinor: 12900),
      );
      final s = (await h.cashStore.find(id))!;
      expect(s.close!.incomeMinor, '4000');
      expect(s.close!.expenseMinor, '1000');
      expect(s.close!.expectedMinor, '13000');
      expect(s.close!.differenceMinor, '-100');
      expect((await h.db.select(h.db.financialEntries).get()).length, 4);
    },
  );
  test(
    'requiere apertura, guarda atómicamente y retry de operación tras cierre',
    () async {
      final cmd = await h.command();
      await expectLater(h.finance.registrar(cmd), throwsStateError);
      expect(await h.db.select(h.db.financialEntries).get(), isEmpty);
      final id = await h.open();
      final e = await h.finance.registrar(cmd);
      await h.cash.cerrar(
        CerrarCajaCommand(sessionId: id, countedMinor: 12500),
      );
      expect(await h.finance.registrar(cmd), e);
      expect((await h.cashStore.movements(id)).length, 1);
    },
  );
  test(
    'operación preparada contra apertura cerrada revierte origen y evento',
    () async {
      final id = await h.open();
      final cmd = await h.command();
      final cat = await h.categories.findById(cmd.categoryId);
      final binding = await h.cash.binding(method: 'cash', amountMinor: 1);
      final p = MovimientoFinancieroRegistradoPayload.fromJson({
        'category_id': cat!.id,
        'category_event_id': cat.createdEventId,
        'category_name_snapshot': cat.name,
        'direction': 'in',
        'nature': 'operating',
        'amount_minor': 1,
        'currency': 'MXN',
        'method': 'cash',
        'occurred_at_ms': 1,
        'cash': binding!.toJson(),
      });
      await h.cash.cerrar(
        CerrarCajaCommand(sessionId: id, countedMinor: 10000),
      );
      final e = SyncEvent(
        eventId: const Uuid().v4(),
        aggregateId: cmd.entryId,
        aggregateType: MovimientoFinancieroRegistradoPayload.aggregateType,
        eventType: MovimientoFinancieroRegistradoPayload.eventType,
        deviceId: h.context.deviceId,
        userId: h.context.userId,
        createdAtLocal: DateTime.now(),
        baseVersion: 1,
        payload: p.toJson(),
      );
      await expectLater(
        h.events.appendAndApply(e, refs: p.refs(cmd.entryId)),
        throwsStateError,
      );
      expect(await h.entries.findById(cmd.entryId), isNull);
      expect(await h.persistence.eventById(e.eventId), isNull);
    },
  );
  test(
    'cierre y nueva apertura offline mantienen cadena causal y movimientos separados',
    () async {
      final a = await h.open();
      await h.entry();
      final c = await h.cash.cerrar(
        CerrarCajaCommand(sessionId: a, countedMinor: 12500),
      );
      final b = await h.open(amount: 0);
      await h.entry(amount: 100);
      expect((await h.cashStore.find(b))!.previousCloseEventId, c);
      expect((await h.cashStore.movements(a)).length, 1);
      expect((await h.cashStore.movements(b)).single.amountMinor, 100);
    },
  );
  test('acumulación BigInt excede entero seguro sin perder centavos', () async {
    final id = await h.open(amount: 9007199254740991);
    await h.entry(amount: 9007199254740991);
    await h.entry(amount: 9007199254740991);
    await h.cash.cerrar(CerrarCajaCommand(sessionId: id, countedMinor: 0));
    expect(
      (await h.cashStore.find(id))!.close!.expectedMinor,
      '27021597764222973',
    );
  });
  test(
    'eventos históricos sin asociación no generan caja retrospectiva',
    () async {
      await h.entry(drawer: false);
      final id = await h.open();
      expect(await h.cashStore.movements(id), isEmpty);
    },
  );
  test(
    'standalone termina localmente, valida refs y no persiste event_refs',
    () async {
      await h.dispose();
      h = CashHarness(mode: AppMode.standalone);
      final id = await h.open();
      await h.entry();
      await h.cash.cerrar(
        CerrarCajaCommand(sessionId: id, countedMinor: 12500),
      );
      expect(await h.db.select(h.db.eventRefs).get(), isEmpty);
      expect(
        (await h.db.select(h.db.events).get()).every(
          (e) => e.deliveryStatus == 'not_required',
        ),
        true,
      );
      await expectLater(
        h.events.appendAndApply(
          SyncEvent(
            eventId: 'bad',
            aggregateId: 'bad',
            aggregateType: 'cash_session',
            eventType: 'caja_abierta',
            deviceId: '',
            userId: '',
            createdAtLocal: DateTime.now(),
            payload: {},
          ),
          refs: const <LocalEventRef>[],
        ),
        throwsArgumentError,
      );
    },
  );
}
