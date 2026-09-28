import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/cuenta/declarar_saldo_cuenta_inicial_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/revalidation/account_balance_pending_event_validator.dart';
import 'package:pos_flutter/application/sync/revalidation/pending_conflict.dart';
import 'package:pos_flutter/domain/cuenta/account_balance_baseline.dart';

import '../../../support/cuenta_harness.dart';

void main() {
  late CuentaHarness h;
  setUp(() => h = CuentaHarness());
  tearDown(() => h.dispose());

  /// Eco del servidor: el evento se acepta y la proyección avanza su secuencia.
  Future<void> accept(String eventId, int sequence) async {
    await h.persistence.updateEventSyncStatus(
      eventId,
      'delivered',
      serverSequence: sequence,
    );
    await h.store.acknowledge(eventId, sequence);
  }

  test('declarar crea un solo hecho pendiente y lo entrega el servidor', () async {
    final eventId = await h.declarar(amountMinor: 12345);

    final pending = await h.repository.watchBaseline().first;
    expect(pending!.amountMinor, 12345);
    expect(pending.deviceId, 'bank-tablet');
    expect(pending.deliveryStatus, 'pending');
    expect(pending.isDelivered, isFalse);
    expect(pending.needsAttention, isFalse);
    // La frontera se sella al declarar, y es posterior a la captura.
    expect(pending.asOfMs, greaterThan(0));

    // El evento sale con la sobre y las referencias que hacen única la ranura.
    final sent = (await h.persistence.pendingEvents()).single;
    expect(sent.eventId, eventId);
    expect(sent.aggregateType, 'account_balance_baseline');
    expect(sent.eventType, 'saldo_cuenta_inicial_declarado');
    expect(sent.baseVersion, 1);
    final refs = await h.persistence.refsForEvents([eventId]);
    expect(
      refs
          .where((r) => r.relationship == 'requires_unique')
          .map((r) => '${r.refType}/${r.refId}'),
      ['account_balance_slot/unica'],
    );
    expect(
      refs
          .where((r) => r.relationship == 'affects')
          .map((r) => r.refType),
      ['account_balance_baseline'],
    );

    await accept(eventId, 42);

    final delivered = await h.repository.watchBaseline().first;
    expect(delivered!.deliveryStatus, 'delivered');
    expect(delivered.isDelivered, isTrue);
    // El hecho no cambia: el mismo importe y la misma frontera.
    expect(delivered.amountMinor, pending.amountMinor);
    expect(delivered.asOfMs, pending.asOfMs);
    expect((await h.store.only())!.lastServerSequence, 42);
  });

  test('un saldo sobregirado es una declaración legítima', () async {
    await h.declarar(amountMinor: -7500);

    final baseline = await h.repository.watchBaseline().first;
    expect(baseline!.amountMinor, -7500);
    expect(baseline.deliveryStatus, 'pending');
  });

  test('una segunda declaración se rechaza sin tocar la primera', () async {
    await h.declarar(amountMinor: 10000);

    await expectLater(
      h.declarar(amountMinor: 20000),
      throwsA(isA<StateError>()),
    );

    expect((await h.store.only())!.amountMinor, 10000);
    expect(await h.persistence.pendingEvents(), hasLength(1));
  });

  test('reintentar la misma declaración con la misma identidad es idempotente', () async {
    const baselineId = '11111111-1111-4111-8111-111111111111';
    final first = await h.cuenta.declarar(declarar(baselineId, 10000));
    final again = await h.cuenta.declarar(declarar(baselineId, 10000));

    expect(again, first);
    expect(await h.persistence.pendingEvents(), hasLength(1));
  });

  test('reintentar la misma identidad con otro importe se rechaza', () async {
    const baselineId = '11111111-1111-4111-8111-111111111111';
    await h.cuenta.declarar(declarar(baselineId, 10000));

    await expectLater(
      h.cuenta.declarar(declarar(baselineId, 999)),
      throwsA(isA<StateError>()),
    );
    expect((await h.store.only())!.amountMinor, 10000);
  });

  test('otra terminal que declara después del eco se rechaza sin escribir', () async {
    final eventId = await h.declarar();
    await accept(eventId, 7);

    // Mismo evento, distinta identidad y otro terminal: el slot único manda.
    final foreign = SyncEvent(
      eventId: '22222222-2222-4222-8222-222222222222',
      aggregateType: 'account_balance_baseline',
      aggregateId: '33333333-3333-4333-8333-333333333333',
      eventType: 'saldo_cuenta_inicial_declarado',
      deviceId: 'other-tablet',
      userId: 'other-user',
      createdAtLocal: DateTime.now().toUtc(),
      baseVersion: 1,
      serverSequence: 8,
      payload: const {
        'amount_minor': 999,
        'as_of_ms': 1789041600000,
      },
    );

    await expectLater(
      h.events.appendAndApply(
        foreign,
        refs: const [
          LocalEventRef.affects(
            refType: 'account_balance_baseline',
            refId: '33333333-3333-4333-8333-333333333333',
          ),
          LocalEventRef.requiresUnique(
            refType: 'account_balance_slot',
            refId: 'unica',
          ),
        ],
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      (await h.store.only())!.createdEventId,
      eventId,
    );
    expect((await h.persistence.pendingEvents()), isEmpty);
  });

  test('el servidor acepta el eco del mismo hecho y no lo duplica', () async {
    final eventId = await h.declarar(amountMinor: 2500);

    final echo = (await h.persistence.eventById(eventId))!.copyWith(
      serverSequence: 11,
    );
    await h.handler.apply(echo);

    final baseline = await h.store.find(
      (await h.store.only())!.id,
    );
    expect(baseline!.lastServerSequence, 11);
    expect(
      (await h.db.select(h.db.accountBalanceBaselines).get()),
      hasLength(1),
    );
  });

  group('ajuste de la instalacion', () {
    test('sin bankEnabled no se declara nada', () async {
      h.setBankEnabled(false);

      await expectLater(
        h.declarar(),
        throwsA(isA<StateError>()),
      );
      expect(await h.persistence.pendingEvents(), isEmpty);
      expect(await h.store.only(), isNull);
    });

    test('el ajuste sobrevive al viaje por json', () {
      final off = h.config.config.copyWith(bankEnabled: false);
      expect(off.toJson()['bank_enabled'], isFalse);
      expect(
        AppConfig.fromJson(off.toJson()).bankEnabled,
        isFalse,
      );
      // Una instalacion sin la clave se considera habilitada.
      expect(
        AppConfig.fromJson(h.config.config.toJson()).bankEnabled,
        isTrue,
      );
    });
  });

  group('revalidacion de pendientes', () {
    test('sin otra declaracion, la pendiente sigue siendo enviable', () async {
      final eventId = await h.declarar();
      final event = (await h.persistence.eventById(eventId))!;
      final validator = AccountBalancePendingEventValidator(h.store);

      expect(await validator.validate(event, {}), isNull);
    });

    test('si otra terminal declaro primero, la pendiente pide revision', () async {
      final eventId = await h.declarar();
      final event = (await h.persistence.eventById(eventId))!;
      // Llega la declaracion de otra terminal: el servidor la va a rechazar.
      await h.db.customStatement(
        "INSERT INTO account_balance_baselines(id,device_id,declared_by_user_id,amount_minor,as_of_ms,created_event_id,last_event_id) "
        "VALUES('44444444-4444-4444-8444-444444444444','other-tablet','other-user',1,1,'55555555-5555-4555-8555-555555555555','55555555-5555-4555-8555-555555555555')",
      );

      final validator = AccountBalancePendingEventValidator(h.store);
      final conflict = await validator.validate(event, {});

      expect(conflict, isA<PendingConflict>());
      expect(conflict!.reason, contains('otra terminal'));
      // La revalidacion no borra ni reabre nada.
      expect((await h.store.only())!.createdEventId, eventId);
    });
  });

  test('el hecho declarado no se borra al apagar el ajuste', () async {
    final eventId = await h.declarar();
    h.setBankEnabled(false);

    expect((await h.store.only())!.createdEventId, eventId);
    expect(
      await h.repository.watchBaseline().first,
      isA<AccountBalanceBaseline>(),
    );
  });
}

/// Deja el comando legible en los reintentos por identidad.
DeclararSaldoCuentaInicialCommand declarar(String baselineId, int amountMinor) =>
    DeclararSaldoCuentaInicialCommand(
      baselineId: baselineId,
      amountMinor: amountMinor,
    );
