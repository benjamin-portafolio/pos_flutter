import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/sync/categoria_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/categoria_movida_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/financial_category_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/financial_entry_event_handler.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/categoria_financiera_creada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/movimiento_financiero_registrado_payload.dart';
import 'package:pos_flutter/application/sync/remote_event_applier.dart';
import 'package:pos_flutter/application/sync/server_echo_acknowledger.dart';
import 'package:pos_flutter/application/sync/sync_conflict_projection_cleaner.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_pull_service.dart';
import 'package:pos_flutter/application/sync/sync_push_service.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_espacio_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_financial_category_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_financial_entry_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';
import 'package:pos_flutter/data/local/drift/drift_synced_event_store.dart';

import '../test/fixtures/financial_fixture_loader.dart';

// Prueba esencial A/B contra servidor PostgreSQL aislado real (HTTP verdadero).
// Requiere el servidor NestJS corriendo: ver `Estado y continuidad.md`.
// Base URL por defecto http://localhost:3210, override con E2E_SYNC_BASE_URL.
const _rentaId = '11111111-1111-4111-8111-111111111111';
const _rentaEventId = '22222222-2222-4222-8222-222222222222';
const _cashEntryId = '33333333-3333-4333-8333-333333333333';
const _cashEventId = '44444444-4444-4444-8444-444444444444';
const _transferEntryId = '55555555-5555-4555-8555-555555555555';
const _transferEventId = '66666666-6666-4666-8666-666666666666';

void main() {
  final baseUrl = Platform.environment['E2E_SYNC_BASE_URL'] ??
      'http://localhost:3210';

  late AppDatabase dbA;
  late AppDatabase dbB;
  final client = http.Client();

  DriftFinancialCategoryProjectionStore catStore(AppDatabase target) =>
      DriftFinancialCategoryProjectionStore(
        db: target,
        dao: target.financialCategoryDao,
      );
  DriftFinancialEntryProjectionStore entryStore(AppDatabase target) =>
      DriftFinancialEntryProjectionStore(
        db: target,
        dao: target.financialEntryDao,
      );

  DriftSyncPersistence persistence(AppDatabase target) => DriftSyncPersistence(
    db: target,
    eventDao: target.eventDao,
    eventRefDao: target.eventRefDao,
    syncCheckpointDao: target.syncCheckpointDao,
  );

  EventProcessor processor(AppDatabase target) => EventProcessor(
    handlers: {
      CategoriaFinancieraCreadaPayload.eventType:
          FinancialCategoryEventHandler(catStore(target)).apply,
      MovimientoFinancieroRegistradoPayload.eventType: (event) async {
        await FinancialEntryEventHandler(entryStore(target), catStore(target))
            .apply(event);
      },
    },
  );

  DriftLocalEventStore localEvents(AppDatabase target) => DriftLocalEventStore(
    db: target,
    eventDao: target.eventDao,
    eventRefDao: target.eventRefDao,
    eventProcessor: processor(target),
  );

  SyncPushService pushService(AppDatabase target) => SyncPushService(
    syncPersistence: persistence(target),
    endpointConfig: SyncEndpointConfig(initialBaseUrl: baseUrl),
    client: client,
    conflictProjectionCleaner: _cleaner(target),
  );

  SyncPullService pullService(AppDatabase target, LocalCommandContext ctx) =>
      SyncPullService(
        syncPersistence: persistence(target),
        remoteEventApplier: RemoteEventApplier(
          eventStore: DriftSyncedEventStore(db: target),
          eventProcessor: processor(target),
          serverEchoAcknowledger: ServerEchoAcknowledger(
            categoriaProjectionStore: DriftCategoriaProjectionStore(
              categoriaDao: target.categoriaDao,
            ),
            financialCategoryProjectionStore: catStore(target),
            financialEntryProjectionStore: entryStore(target),
          ),
        ),
        endpointConfig: SyncEndpointConfig(initialBaseUrl: baseUrl),
        commandContext: ctx,
        client: client,
      );

  setUpAll(() async {
    dbA = AppDatabase.forTesting(NativeDatabase.memory());
    dbB = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDownAll(() async {
    await dbA.close();
    await dbB.close();
    client.close();
  });

  Future<SyncEvent> appendCategory(AppDatabase target,
      {String? eventId}) async {
    const payload = <String, Object?>{
      'name': 'Renta',
      'direction': 'out',
      'nature': 'operating',
    };
    final event = SyncEvent(
      eventId: eventId ?? _rentaEventId,
      aggregateType: CategoriaFinancieraCreadaPayload.aggregateType,
      aggregateId: _rentaId,
      eventType: CategoriaFinancieraCreadaPayload.eventType,
      deviceId: 'tablet_a',
      userId: 'user_01',
      createdAtLocal: DateTime.utc(2026, 9, 24, 12),
      baseVersion: 1,
      payload: payload,
    );
    await localEvents(target).appendAndApply(
      event,
      refs: CategoriaFinancieraCreadaPayload.fromJson(
        payload,
      ).refs(event.aggregateId),
    );
    return event;
  }

  Future<SyncEvent> appendEntry(
    AppDatabase target, {
    required String entryId,
    required String eventId,
    required String fixturePath,
  }) async {
    final payload = Map<String, Object?>.from(
      readFinancialFixture(fixturePath),
    );
    final event = SyncEvent(
      eventId: eventId,
      aggregateType: MovimientoFinancieroRegistradoPayload.aggregateType,
      aggregateId: entryId,
      eventType: MovimientoFinancieroRegistradoPayload.eventType,
      deviceId: 'tablet_a',
      userId: 'user_01',
      createdAtLocal: DateTime.utc(2026, 9, 24, 12),
      baseVersion: 1,
      payload: payload,
    );
    await localEvents(target).appendAndApply(
      event,
      refs: MovimientoFinancieroRegistradoPayload.fromJson(
        payload,
      ).refs(event.aggregateId),
    );
    return event;
  }

  test(
    'A/B aislado real: tablet A crea y sincroniza categoría + 2 registros; '
    'tablet B recibe todo desde since=0 en orden causal; duplicate respeta '
    'original_sync_status',
    () async {
      // ------- A: cliente tablet ------- //
      await appendCategory(dbA);
      await appendEntry(
        dbA,
        entryId: _cashEntryId,
        eventId: _cashEventId,
        fixturePath: 'registro/entry-renta-cash-valid.json',
      );
      await appendEntry(
        dbA,
        entryId: _transferEntryId,
        eventId: _transferEventId,
        fixturePath: 'registro/entry-renta-transfer-valid.json',
      );

      // Lote 1: solo la categoría (dependencia causal); lote 2: ambos registros.
      final first = await pushService(dbA).pushPendingEvents();
      expect((first.synced, first.pending, first.total), (1, 2, 3));
      final second = await pushService(dbA).pushPendingEvents();
      expect((second.synced, second.pending), (2, 0));

      for (final (eventId, seq) in [
        (_rentaEventId, 1),
        (_cashEventId, 2),
        (_transferEventId, 3),
      ]) {
        final stored = (await persistence(dbA).eventById(eventId))!;
        expect(stored.deliveryStatus, 'delivered');
        expect(stored.serverSequence, seq);
      }

      // Reenvío del mismo event_id → el servidor responde duplicate con
      // original_sync_status='synced' (contrato §6.2).
      final duplicate = await client.post(
        Uri.parse('$baseUrl/sync/push'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_id': 'tablet_a',
          'last_full_pull_server_sequence': 0,
          'last_preflight_server_sequence': null,
          'events': [
            (await persistence(dbA).eventById(_rentaEventId))!.toPushJson(),
          ],
        }),
      );
      expect(duplicate.statusCode >= 200 && duplicate.statusCode < 300, isTrue,
          reason: 'HTTP ${duplicate.statusCode}: ${duplicate.body}');
      final duplicateBody =
          (jsonDecode(duplicate.body) as Map).cast<String, Object?>();
      final result =
          ((duplicateBody['results'] as List).single as Map).cast<
            String,
            Object?
          >();
      expect(result['event_id'], _rentaEventId);
      expect(result['status'], 'duplicate');
      expect(result['original_sync_status'], 'synced');

      // ------- B: cliente tablet nuevo, desde since=0 ------- //
      const ctxB = LocalCommandContext(userId: 'user_02', deviceId: 'tablet_b');
      final pull = await pullService(dbB, ctxB).pullAvailableEvents();
      expect((pull.total, pull.lastCursor), (3, 3));

      final category = (await dbB.select(dbB.financialCategories).get()).single;
      expect(category.name, 'Renta');
      expect(category.direction, 'out');
      expect(category.nature, 'operating');
      expect(category.createdEventId, _rentaEventId);
      expect(category.version, 1);

      final entries = await dbB.select(dbB.financialEntries).get();
      expect(entries, hasLength(2));
      final cash = entries.singleWhere((e) => e.id == _cashEntryId);
      final transfer = entries.singleWhere((e) => e.id == _transferEntryId);
      expect(cash.amountMinor, 50000);
      expect(transfer.amountMinor, 150000);
      expect(cash.method, 'cash');
      expect(transfer.method, 'transfer');
      expect(cash.categoryId, _rentaId);
      expect(transfer.categoryId, _rentaId);
      expect(cash.categoryNameSnapshot, 'Renta');
      expect(transfer.categoryNameSnapshot, 'Renta');

      final events = await dbB.select(dbB.events).get();
      expect(events, hasLength(3));
      for (final e in events) {
        expect(e.deliveryStatus, 'delivered');
        expect(e.applicationStatus, 'applied');
        expect(e.serverSequence, isNotNull);
      }
      // Checkpoint atómico avanzó a la última secuencia del servidor.
      expect(
        await persistence(dbB).lastFullPullServerSequence(),
        3,
      );

      // Reflejo de la dependencia causal en el cliente: el applier aplicó la
      // categoría (secuencia 1) antes que los registros (2 y 3), por eso las
      // proyecciones de los registros existen. El cliente no persiste refs
      // para eventos que llegan solos por pull (los refs locales se crean en
      // el append local; el servidor guarda los suyos).
    },
  );
}

SyncConflictProjectionCleaner _cleaner(AppDatabase target) {
  final categories = DriftCategoriaProjectionStore(
    categoriaDao: target.categoriaDao,
  );
  return SyncConflictProjectionCleaner(
    espacioProjectionStore: DriftEspacioProjectionStore(
      espacioDao: target.espacioDao,
    ),
    categoriaProjectionStore: categories,
    categoriaConflictProjectionRestorer:
        CategoriaConflictProjectionRestorer(categories),
    categoriaMovidaConflictProjectionRestorer:
        CategoriaMovidaConflictProjectionRestorer(categories),
  );
}