import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_flutter/application/commands/finanzas/categoria_financiera_command_service.dart';
import 'package:pos_flutter/application/commands/finanzas/crear_categoria_financiera_command.dart';
import 'package:pos_flutter/application/commands/finanzas/movimiento_financiero_command_service.dart';
import 'package:pos_flutter/application/commands/finanzas/registrar_movimiento_financiero_command.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/categoria_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/categoria_movida_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/financial_category_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/financial_entry_event_handler.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/categoria_financiera_creada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/movimiento_financiero_registrado_payload.dart';
import 'package:pos_flutter/application/sync/pending_event_revalidator.dart';
import 'package:pos_flutter/application/sync/remote_event_applier.dart';
import 'package:pos_flutter/application/sync/server_echo_acknowledger.dart';
import 'package:pos_flutter/application/sync/sync_availability_monitor.dart';
import 'package:pos_flutter/application/sync/sync_conflict_projection_cleaner.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_pull_service.dart';
import 'package:pos_flutter/application/sync/sync_push_service.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_espacio_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_financial_category_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_financial_entry_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';
import 'package:pos_flutter/data/local/drift/drift_synced_event_store.dart';
import 'package:pos_flutter/domain/finanzas/financial_direction.dart';
import 'package:pos_flutter/domain/finanzas/financial_nature.dart';

import '../../fixtures/financial_fixture_loader.dart';

// Identidades estables del fixture `offline/ids-referencia.json` (contrato §4).
const _rentaId = '11111111-1111-4111-8111-111111111111';
const _rentaEventId = '22222222-2222-4222-8222-222222222222';
const _cashEntryId = '33333333-3333-4333-8333-333333333333';
const _cashEventId = '44444444-4444-4444-8444-444444444444';
const _transferEntryId = '55555555-5555-4555-8555-555555555555';
const _transferEventId = '66666666-6666-4666-8666-666666666666';

void main() {
  late AppDatabase db;
  bool failEntries = false;
  final context = const LocalCommandContext(userId: 'user', deviceId: 'tablet');

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

  EventProcessor processor(AppDatabase target) {
    final categories = catStore(target);
    return EventProcessor(
      handlers: {
        CategoriaFinancieraCreadaPayload.eventType:
            FinancialCategoryEventHandler(categories).apply,
        MovimientoFinancieroRegistradoPayload.eventType: (event) async {
          if (failEntries) throw StateError('Falla inyectada al aplicar registro');
          await FinancialEntryEventHandler(entryStore(target), categories).apply(
            event,
          );
        },
      },
    );
  }

  DriftLocalEventStore localEvents(AppDatabase target,
      [AppConfigController? controller]) => DriftLocalEventStore(
    db: target,
    eventDao: target.eventDao,
    eventRefDao: target.eventRefDao,
    appConfigController: controller,
    eventProcessor: processor(target),
  );

  SyncConflictProjectionCleaner cleaner(AppDatabase target) {
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

  PendingEventRevalidator revalidator(AppDatabase target) {
    final categories = DriftCategoriaProjectionStore(
      categoriaDao: target.categoriaDao,
    );
    return PendingEventRevalidator(
      syncPersistence: persistence(target),
      syncedEventHistory: persistence(target),
      espacioProjectionStore: DriftEspacioProjectionStore(
        espacioDao: target.espacioDao,
      ),
      categoriaProjectionStore: categories,
      financialCategoryProjectionStore: catStore(target),
      categoriaConflictProjectionRestorer:
          CategoriaConflictProjectionRestorer(categories),
      categoriaMovidaConflictProjectionRestorer:
          CategoriaMovidaConflictProjectionRestorer(categories),
    );
  }

  SyncPushService pushService(AppDatabase target, http.Client client) =>
      SyncPushService(
        syncPersistence: persistence(target),
        endpointConfig: SyncEndpointConfig(
          initialBaseUrl: 'http://localhost:3000',
        ),
        client: client,
        conflictProjectionCleaner: cleaner(target),
      );

  SyncPullService pullService(AppDatabase target, http.Client client) =>
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
        endpointConfig: SyncEndpointConfig(
          initialBaseUrl: 'http://localhost:3000',
        ),
        commandContext: context,
        client: client,
      );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    failEntries = false;
  });

  tearDown(() async {
    await db.close();
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
      deviceId: 'device_tablet_01',
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
      deviceId: 'device_tablet_01',
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

  group('push: dependencia causal y dos registros sin conflicto de versión',
      () {
    test('categoría → cash → transfer en orden y sin reenviar pendientes',
        () async {
      await appendCategory(db);
      await appendEntry(
        db,
        entryId: _cashEntryId,
        eventId: _cashEventId,
        fixturePath: 'registro/entry-renta-cash-valid.json',
      );
      await appendEntry(
        db,
        entryId: _transferEntryId,
        eventId: _transferEventId,
        fixturePath: 'registro/entry-renta-transfer-valid.json',
      );

      var requestCount = 0;
      final service = pushService(
        db,
        MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final sent = (body['events'] as List).cast<Map<String, Object?>>();
          final eventIds =
              sent.map((e) => e['event_id']).cast<String>().toList();
          // Lote 1: solo la categoría; lote 2: cash + transfer juntos.
          if (requestCount == 0) {
            expect(eventIds, [_rentaEventId]);
          } else {
            expect(eventIds, [_cashEventId, _transferEventId]);
            for (final event in sent) {
              expect(
                event['payload'],
                containsPair('category_event_id', _rentaEventId),
              );
            }
          }
          requestCount++;
          return http.Response(
            jsonEncode({
              'results': [
                for (final eventId in eventIds)
                  {
                    'event_id': eventId,
                    'status': 'accepted',
                    'server_sequence': eventId == _rentaEventId
                        ? 1
                        : eventId == _cashEventId
                            ? 2
                            : 3,
                    'created_at_server': '2026-09-24T12:10:00.000Z',
                  },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );

      final first = await service.pushPendingEvents();
      expect((first.synced, first.pending, first.total), (1, 2, 3));
      expect(
        (await persistence(db).eventById(_rentaEventId))!.deliveryStatus,
        'delivered',
      );
      expect(
        (await persistence(db).eventById(_cashEventId))!.deliveryStatus,
        'pending',
      );

      final second = await service.pushPendingEvents();
      expect((second.synced, second.pending), (2, 0));
      expect(requestCount, 2);

      for (final eventId in [_cashEventId, _transferEventId]) {
        expect(
          (await persistence(db).eventById(eventId))!.deliveryStatus,
          'delivered',
        );
        expect(
          (await persistence(db).eventById(eventId))!.serverSequence,
          eventId == _cashEventId ? 2 : 3,
        );
      }
      final refs = await db.select(db.eventRefs).get();
      expect(refs.map((r) => r.source).toSet(), {'server'});
      expect(refs.map((r) => r.serverSequence).toSet(), {1, 2, 3});
      expect(refs.where((r) => r.relationship == 'uses').length, 2);

      // Dos registros comparten categoría: la categoría nunca compite por versión.
      final category = (await db.select(db.financialCategories).get()).single;
      expect(category.version, 1);
      expect(category.lastServerSequence, isNull);
      expect(await db.select(db.financialEntries).get(), hasLength(2));
    });
  });

  group('duplicate respeta original_sync_status', () {
    for (final (remoteStatus, originalStatus, expectedStatus) in const [
      ('duplicate', null, 'delivered'),
      ('duplicate', 'synced', 'delivered'),
      ('duplicate', 'delivered', 'delivered'),
      ('duplicate', 'rejected', 'rejected'),
      ('duplicate', 'pending', 'pending'),
      ('duplicate', 'conflict', 'conflict'),
      ('conflict', null, 'conflict'),
    ]) {
      test('$remoteStatus/$originalStatus → $expectedStatus', () async {
        final event = await appendCategory(db);
        final service = pushService(
          db,
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'results': [
                  {
                    'event_id': event.eventId,
                    'status': remoteStatus,
                    'original_sync_status': ?originalStatus,
                    'server_sequence': 13,
                    'created_at_server': '2026-09-24T12:10:00.000Z',
                    'reason': 'Incidencia de entrega (duplicate).',
                  },
                ],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            ),
          ),
        );

        final report = await service.pushPendingEvents();
        final stored = (await persistence(db).eventById(event.eventId))!;
        expect(stored.deliveryStatus, expectedStatus);
        expect(
          stored.serverSequence,
          expectedStatus == 'pending' ? isNull : 13,
        );
        final ref = (await db.select(db.eventRefs).get()).single;
        expect(
          ref.source,
          expectedStatus == 'pending' ? 'local_pending' : 'server',
        );
        expect(
          ref.serverSequence,
          expectedStatus == 'pending' ? isNull : 13,
        );
        expect(report.synced, expectedStatus == 'delivered' ? 1 : 0);
        expect(report.rejected, expectedStatus == 'rejected' ? 1 : 0);
        expect(report.conflicts, expectedStatus == 'conflict' ? 1 : 0);
        expect(report.pending, expectedStatus == 'pending' ? 1 : 0);

        // El hecho financiero permanece local en cualquier incidencia.
        final category = (await db.select(db.financialCategories).get()).single;
        expect(category.name, 'Renta');
        expect(category.version, 1);
        expect(
          category.createdEventId,
          event.eventId,
        );
      });
    }
  });

  test('propaga conflicto de categoría al registro sin borrar el dinero', () async {
    final category = await appendCategory(db);
    final cash = await appendEntry(
      db,
      entryId: _cashEntryId,
      eventId: _cashEventId,
      fixturePath: 'registro/entry-renta-cash-valid.json',
    );

    var requests = 0;
    final service = pushService(
      db,
      MockClient((request) async {
        requests++;
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final sent = (body['events'] as List).cast<Map>().single;
        expect(sent['event_id'], category.eventId);
        return http.Response(
          jsonEncode({
            'results': [
              {
                'event_id': category.eventId,
                'status': 'conflict',
                'server_sequence': 7,
                'reason': 'La categoría coincide con una oficial distinta.',
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final report = await service.pushPendingEvents();

    expect(requests, 1);
    expect((report.total, report.conflicts, report.pending), (2, 2, 0));
    final storedCategory = (await persistence(db).eventById(
      category.eventId,
    ))!;
    final storedCash = (await persistence(db).eventById(cash.eventId))!;
    expect(storedCategory.deliveryStatus, 'conflict');
    expect(storedCategory.rejectionReason, contains('oficial distinta'));
    expect(storedCash.deliveryStatus, 'conflict');
    expect(
      storedCash.rejectionReason,
      'El evento depende de otro evento local en conflicto.',
    );
    // Limpieza de conflicto (no-op) conserva categoría y registros referenciados.
    expect(await db.select(db.financialCategories).get(), hasLength(1));
    expect(await db.select(db.financialEntries).get(), hasLength(1));
    final entry = (await db.select(db.financialEntries).get()).single;
    expect(entry.amountMinor, 50000);
    expect(entry.categoryId, _rentaId);
  });

  test('revalidación conserva registros referenciados por categoría en colisión',
      () async {
    final localCategory = await appendCategory(db);
    final cash = await appendEntry(
      db,
      entryId: _cashEntryId,
      eventId: _cashEventId,
      fixturePath: 'registro/entry-renta-cash-valid.json',
    );

    // El oficial con la misma identidad (otro evento de creación) reemplaza la
    // alta local por upsert; la FK RESTRICT protege las entries.
    await FinancialCategoryEventHandler(catStore(db)).apply(
      SyncEvent(
        eventId: 'official-category-event',
        aggregateType: CategoriaFinancieraCreadaPayload.aggregateType,
        aggregateId: _rentaId,
        eventType: CategoriaFinancieraCreadaPayload.eventType,
        deviceId: 'device_tablet_02',
        userId: 'user_02',
        createdAtLocal: DateTime.utc(2026, 9, 24, 13),
        baseVersion: 1,
        serverSequence: 9,
        payload: const {
          'name': 'Renta oficial',
          'direction': 'out',
          'nature': 'operating',
        },
      ),
    );

    final report = await revalidator(db).revalidatePendingEvents();
    expect((report.checked, report.conflicts), (2, 2));

    final storedCategory = (await persistence(db).eventById(
      localCategory.eventId,
    ))!;
    final storedCash = (await persistence(db).eventById(cash.eventId))!;
    expect(storedCategory.deliveryStatus, 'conflict');
    expect(
      storedCategory.rejectionReason,
      'Ya existe una categoría financiera con id $_rentaId.',
    );
    expect(storedCash.deliveryStatus, 'conflict');
    expect(
      storedCash.rejectionReason,
      'Operación registrada: la categoría financiera no se puede sincronizar. Requiere atención.',
    );

    final categories = await db.select(db.financialCategories).get();
    expect(categories, hasLength(1));
    expect(categories.single.name, 'Renta oficial');
    expect(categories.single.createdEventId, 'official-category-event');
    expect(categories.single.version, 1);
    expect(await db.select(db.financialEntries).get(), hasLength(1));
    expect(
      (await db.select(db.financialEntries).get()).single.amountMinor,
      50000,
    );
  });

  test('eco vía pull solo avanza last_server_sequence', () async {
    await appendCategory(db);
    final cash = await appendEntry(
      db,
      entryId: _cashEntryId,
      eventId: _cashEventId,
      fixturePath: 'registro/entry-renta-cash-valid.json',
    );

    final service = pullService(
      db,
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'events': [
              _remoteCategoryEvent(
                eventId: _rentaEventId,
                serverSequence: 12,
              ),
              _remoteEntryEvent(
                eventId: _cashEventId,
                aggregateId: _cashEntryId,
                serverSequence: 40,
                payload: readFinancialFixture(
                  'registro/entry-renta-cash-valid.json',
                ),
              ),
            ],
            'next_cursor': 40,
            'has_more': false,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );

    final report = await service.pullAvailableEvents();
    expect((report.total, report.lastCursor), (2, 40));

    final category = (await db.select(db.financialCategories).get()).single;
    expect(category.lastServerSequence, 12);
    expect(category.name, 'Renta');
    expect(category.version, 1);
    expect(category.createdEventId, _rentaEventId);

    final entries = await db.select(db.financialEntries).get();
    expect(entries, hasLength(1));
    expect(entries.single.amountMinor, 50000);
    expect(entries.single.method, 'cash');
    expect(entries.single.lastServerSequence, 40);
    expect(entries.single.version, 1);
    expect(entries.single.createdEventId, cash.eventId);

    final events = await db.select(db.events).get();
    expect(
      events.map((e) => e.deliveryStatus).toSet(),
      {'delivered'},
    );
    expect(
      events.map((e) => e.serverSequence).toSet(),
      {12, 40},
    );
    expect(await persistence(db).lastFullPullServerSequence(), 40);
  });

  group('pull a un segundo cliente vacío con checkpoint atómico', () {
    test('base vacía recibe categoría + cash + transfer desde since=0', () async {
      final second = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(second.close);
      var requests = 0;
      final service = pullService(
        second,
        MockClient((request) async {
          expect(request.url.queryParameters['since'], '0');
          requests++;
          return http.Response(
            jsonEncode({
              'events': [
                _remoteCategoryEvent(
                  eventId: _rentaEventId,
                  serverSequence: 1,
                ),
                _remoteEntryEvent(
                  eventId: _cashEventId,
                  aggregateId: _cashEntryId,
                  serverSequence: 2,
                  payload: readFinancialFixture(
                    'registro/entry-renta-cash-valid.json',
                  ),
                ),
                _remoteEntryEvent(
                  eventId: _transferEventId,
                  aggregateId: _transferEntryId,
                  serverSequence: 3,
                  payload: readFinancialFixture(
                    'registro/entry-renta-transfer-valid.json',
                  ),
                ),
              ],
              'next_cursor': 3,
              'has_more': false,
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );

      final report = await service.pullAvailableEvents();
      expect((report.total, report.lastCursor), (3, 3));
      expect(requests, 1);

      final categories = await second.select(second.financialCategories).get();
      expect(categories, hasLength(1));
      expect(categories.single.id, _rentaId);
      expect(categories.single.lastServerSequence, 1);

      final entries = await second.select(second.financialEntries).get();
      expect(entries, hasLength(2));
      expect(
        entries.map((e) => e.amountMinor).toSet(),
        {50000, 150000},
      );
      expect(
        entries.map((e) => e.method).toSet(),
        {'cash', 'transfer'},
      );
      final cash = entries.singleWhere((e) => e.id == _cashEntryId);
      expect(cash.notes, 'Renta en efectivo');
      final transfer = entries.singleWhere((e) => e.id == _transferEntryId);
      expect(transfer.reference, 'SPEI-2026-09-20');
      expect(
        await second.select(second.events).get(),
        hasLength(3),
      );
      expect(
        await persistence(second).lastFullPullServerSequence(),
        3,
      );
    });

    test('fallo a mitad de página revierte página y checkpoint; retry aplica',
        () async {
      final second = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(second.close);
      http.Response page() => http.Response(
        jsonEncode({
          'events': [
            _remoteCategoryEvent(eventId: _rentaEventId, serverSequence: 1),
            _remoteEntryEvent(
              eventId: _cashEventId,
              aggregateId: _cashEntryId,
              serverSequence: 2,
              payload: readFinancialFixture(
                'registro/entry-renta-cash-valid.json',
              ),
            ),
            _remoteEntryEvent(
              eventId: _transferEventId,
              aggregateId: _transferEntryId,
              serverSequence: 3,
              payload: readFinancialFixture(
                'registro/entry-renta-transfer-valid.json',
              ),
            ),
          ],
          'next_cursor': 3,
          'has_more': false,
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );

      final service = pullService(second, MockClient((_) async => page()));

      failEntries = true;
      await expectLater(
        service.pullAvailableEvents(),
        throwsStateError,
      );

      // Página y checkpoint se revirtieron: sin filas parciales.
      expect(await second.select(second.financialCategories).get(), isEmpty);
      expect(await second.select(second.financialEntries).get(), isEmpty);
      expect(await second.select(second.events).get(), isEmpty);
      expect(
        await persistence(second).lastFullPullServerSequence(),
        0,
      );

      failEntries = false;
      final report = await service.pullAvailableEvents();
      expect((report.total, report.lastCursor), (3, 3));
      expect(await second.select(second.financialEntries).get(), hasLength(2));
      expect(
        await persistence(second).lastFullPullServerSequence(),
        3,
      );
    });
  });

  test('standalone: finanzas sin refs, not_required y sin monitor de sync',
      () async {
    final config = AppConfigController(
      AppConfig.initial.copyWith(
        mode: AppMode.standalone,
        setupCompleted: true,
        backupProvider: BackupProvider.none,
      ),
    );
    addTearDown(config.dispose);
    var syncInstantiations = 0;
    getIt.registerLazySingleton<SyncAvailabilityMonitor>(() {
      syncInstantiations++;
      throw StateError(
        'No debe arrancar health, push, pull, preflight ni WebSocket.',
      );
    });
    addTearDown(() => getIt.unregister<SyncAvailabilityMonitor>());

    await startConfiguredRuntimeServices(config.config);

    final store = localEvents(db, config);
    final catService = CategoriaFinancieraCommandService(
      store: catStore(db),
      events: store,
      context: context,
    );
    final entryService = MovimientoFinancieroCommandService(
      store: entryStore(db),
      categories: catStore(db),
      events: store,
      context: context,
    );
    await catService.crear(
      const CrearCategoriaFinancieraCommand(
        categoryId: _rentaId,
        name: 'Renta',
        direction: FinancialDirection.expense,
        nature: FinancialNature.operating,
      ),
    );
    await entryService.registrar(
      RegistrarMovimientoFinancieroCommand(
        entryId: _cashEntryId,
        categoryId: _rentaId,
        amountMinor: 50000,
        method: 'cash',
        occurredAtMs: 1789041600000,
        notes: 'Renta en efectivo',
      ),
    );

    expect(syncInstantiations, 0);
    expect(await persistence(db).pendingEvents(), isEmpty);
    expect(await db.select(db.eventRefs).get(), isEmpty);
    expect(
      (await db.select(db.events).get()).every(
        (e) => e.deliveryStatus == 'not_required',
      ),
      isTrue,
    );
    expect(await db.select(db.financialCategories).get(), hasLength(1));
    expect(await db.select(db.financialEntries).get(), hasLength(1));
  });
}

Map<String, Object?> _remoteCategoryEvent({
  required String eventId,
  required int serverSequence,
}) {
  return {
    'event_id': eventId,
    'aggregate_type': 'financial_category',
    'aggregate_id': _rentaId,
    'event_type': 'categoria_financiera_creada',
    'device_id': 'device_tablet_02',
    'user_id': 'user_02',
    'local_sequence': 1,
    'server_sequence': serverSequence,
    'base_server_sequence': null,
    'base_version': 1,
    'created_at_local': '2026-09-24T12:00:00.000Z',
    'created_at_server': '2026-09-24T12:05:00.000Z',
    'payload': <String, Object?>{
      'name': 'Renta',
      'direction': 'out',
      'nature': 'operating',
    },
    'sync_status': 'synced',
  };
}

Map<String, Object?> _remoteEntryEvent({
  required String eventId,
  required String aggregateId,
  required int serverSequence,
  required Map<String, Object?> payload,
}) {
  return {
    'event_id': eventId,
    'aggregate_type': 'financial_entry',
    'aggregate_id': aggregateId,
    'event_type': 'movimiento_financiero_registrado',
    'device_id': 'device_tablet_02',
    'user_id': 'user_02',
    'local_sequence': 2,
    'server_sequence': serverSequence,
    'base_server_sequence': null,
    'base_version': 1,
    'created_at_local': '2026-09-24T12:00:00.000Z',
    'created_at_server': '2026-09-24T12:05:00.000Z',
    'payload': payload,
    'sync_status': 'synced',
  };
}