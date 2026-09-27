import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/finanzas/categoria_financiera_command_service.dart';
import 'package:pos_flutter/application/commands/finanzas/crear_categoria_financiera_command.dart';
import 'package:pos_flutter/application/commands/finanzas/movimiento_financiero_command_service.dart';
import 'package:pos_flutter/application/commands/finanzas/registrar_movimiento_financiero_command.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/financial_category_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/financial_entry_event_handler.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/categoria_financiera_creada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/movimiento_financiero_registrado_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_financial_category_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_financial_entry_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';
import 'package:pos_flutter/data/repositories/financial_entry_repository_impl.dart';
import 'package:pos_flutter/domain/finanzas/financial_direction.dart';
import 'package:pos_flutter/domain/finanzas/financial_nature.dart';

import '../../../fixtures/financial_fixture_loader.dart';

// Identidades estables del fixture `offline/ids-referencia.json` (contrato §4).
const _rentaId = '11111111-1111-4111-8111-111111111111';
const _rentaEventId = '22222222-2222-4222-8222-222222222222';
const _cashEntryId = '33333333-3333-4333-8333-333333333333';
const _cashEventId = '44444444-4444-4444-8444-444444444444';
const _transferEntryId = '55555555-5555-4555-8555-555555555555';
const _transferEventId = '66666666-6666-4666-8666-666666666666';
const _ingresoEntryId = '77777777-7777-4777-8777-777777777777';
const _ingresoEventId = '88888888-8888-4888-8888-888888888888';
const _ingresosVariosId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _ingresosVariosEventId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

// Timestamps clave (epoch ms UTC) del fixture `index.md`.
const _fromSep = 1788220800000; // 2026-09-01T00:00:00Z (inclusivo)
const _toOct = 1790812800000; // 2026-10-01T00:00:00Z (exclusivo)
const _cashAt = 1789041600000; // 2026-09-10T12:00:00Z
const _ingresoAt = 1789463700000; // 2026-09-15T09:15:00Z
const _transferAt = 1789929000000; // 2026-09-20T18:30:00Z
const _futuro = 1798804800000; // 2027-01-01T12:00:00Z (rechazado en command)

const _otroEntryId = '99999999-9999-4999-8999-999999999991';
const _futuroEntryId = '99999999-9999-4999-8999-999999999992';

const _bordeToEntryId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const _bordeToEventId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _bordeAntesEntryId = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
const _bordeAntesEventId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

void main() {
  late AppDatabase db;
  late AppConfigController config;
  late Directory directory;
  bool failAfterApply = false;
  final context = const LocalCommandContext(userId: 'user', deviceId: 'tablet');

  DriftFinancialCategoryProjectionStore catStore() =>
      DriftFinancialCategoryProjectionStore(
        db: db,
        dao: db.financialCategoryDao,
      );
  DriftFinancialEntryProjectionStore entryStore() =>
      DriftFinancialEntryProjectionStore(db: db, dao: db.financialEntryDao);

  DriftSyncPersistence persistence() => DriftSyncPersistence(
    db: db,
    eventDao: db.eventDao,
    eventRefDao: db.eventRefDao,
    syncCheckpointDao: db.syncCheckpointDao,
  );

  DriftLocalEventStore events() {
    final categories = catStore();
    return DriftLocalEventStore(
      db: db,
      eventDao: db.eventDao,
      eventRefDao: db.eventRefDao,
      appConfigController: config,
      eventProcessor: EventProcessor(
        handlers: {
          CategoriaFinancieraCreadaPayload.eventType:
              FinancialCategoryEventHandler(categories).apply,
          MovimientoFinancieroRegistradoPayload.eventType: (e) async {
            await FinancialEntryEventHandler(entryStore(), categories).apply(e);
            if (failAfterApply) throw StateError('injected');
          },
        },
      ),
    );
  }

  CategoriaFinancieraCommandService catService() => CategoriaFinancieraCommandService(
    store: catStore(),
    events: events(),
    context: context,
  );

  MovimientoFinancieroCommandService entryService() =>
      MovimientoFinancieroCommandService(
        store: entryStore(),
        categories: catStore(),
        events: events(),
        context: context,
      );

  CrearCategoriaFinancieraCommand rentaCommand() =>
      const CrearCategoriaFinancieraCommand(
        categoryId: _rentaId,
        name: 'Renta',
        direction: FinancialDirection.expense,
        nature: FinancialNature.operating,
      );

  RegistrarMovimientoFinancieroCommand cashCommand() =>
      RegistrarMovimientoFinancieroCommand(
        entryId: _cashEntryId,
        categoryId: _rentaId,
        amountMinor: 50000,
        method: 'cash',
        occurredAtMs: _cashAt,
        notes: 'Renta en efectivo',
      );

  RegistrarMovimientoFinancieroCommand transferCommand() =>
      RegistrarMovimientoFinancieroCommand(
        entryId: _transferEntryId,
        categoryId: _rentaId,
        amountMinor: 150000,
        method: 'transfer',
        occurredAtMs: _transferAt,
        notes: 'Renta de septiembre',
        reference: 'SPEI-2026-09-20',
      );

  Future<void> seedCategory({
    required String id,
    required String eventId,
    required String name,
    required String direction,
    required String nature,
  }) async {
    await db.into(db.financialCategories).insert(
      FinancialCategoriesCompanion.insert(
        id: id,
        name: name,
        direction: direction,
        nature: nature,
        active: const Value(true),
        version: const Value(1),
        createdEventId: Value(eventId),
        lastEventId: Value(eventId),
        lastServerSequence: const Value(null),
      ),
    );
    await db.into(db.events).insert(
      EventsCompanion.insert(
        eventId: eventId,
        aggregateType: CategoriaFinancieraCreadaPayload.aggregateType,
        aggregateId: id,
        eventType: CategoriaFinancieraCreadaPayload.eventType,
        deviceId: 'tablet',
        userId: 'user',
        createdAtLocal: DateTime.utc(2026, 9, 24, 12),
        payload: '{}',
        applicationStatus: const Value('applied'),
        deliveryStatus: const Value('delivered'),
      ),
    );
  }

  Future<void> seedEntry({
    required String id,
    required String eventId,
    required String categoryId,
    required String categoryNameSnapshot,
    required String direction,
    required String nature,
    required int amountMinor,
    required String method,
    required int occurredAtMs,
    String? notes,
    String? reference,
  }) async {
    await db.into(db.financialEntries).insert(
      FinancialEntriesCompanion.insert(
        id: id,
        categoryId: categoryId,
        categoryNameSnapshot: categoryNameSnapshot,
        direction: direction,
        nature: nature,
        amountMinor: amountMinor,
        currency: 'MXN',
        method: method,
        occurredAtMs: occurredAtMs,
        notes: Value(notes),
        reference: Value(reference),
        active: const Value(true),
        version: const Value(1),
        createdEventId: Value(eventId),
        lastEventId: Value(eventId),
        lastServerSequence: const Value(null),
      ),
    );
    await db.into(db.events).insert(
      EventsCompanion.insert(
        eventId: eventId,
        aggregateType: MovimientoFinancieroRegistradoPayload.aggregateType,
        aggregateId: id,
        eventType: MovimientoFinancieroRegistradoPayload.eventType,
        deviceId: 'tablet',
        userId: 'user',
        createdAtLocal: DateTime.utc(2026, 9, 24, 12),
        payload: '{}',
        applicationStatus: const Value('applied'),
        deliveryStatus: const Value('delivered'),
      ),
    );
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('financial_test_');
    db = AppDatabase.forTesting(
      NativeDatabase(File('${directory.path}/test.sqlite')),
    );
    config = AppConfigController(
      AppConfig.initial.copyWith(mode: AppMode.serverSync),
    );
    failAfterApply = false;
  });
  tearDown(() async {
    await db.close();
    await config.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> useMode(AppMode mode) async {
    await config.dispose();
    config = AppConfigController(AppConfig.initial.copyWith(mode: mode));
  }

  for (final mode in AppMode.values) {
    group(mode.name, () {
      test('categoría + 2 registros offline: delivery, refs y versión intacta',
          () async {
        await useMode(mode);
        final catEventId = await catService().crear(rentaCommand());
        final cashEventId = await entryService().registrar(cashCommand());
        final transferEventId = await entryService().registrar(
          transferCommand(),
        );

        final category = (await db.select(db.financialCategories).get()).single;
        expect(category.id, _rentaId);
        expect(category.name, 'Renta');
        expect(category.direction, 'out');
        expect(category.nature, 'operating');
        expect(category.version, 1);
        expect(category.createdEventId, catEventId);

        final entries = await db.select(db.financialEntries).get();
        expect(entries, hasLength(2));
        expect(
          entries.map((e) => e.amountMinor).toSet(),
          {50000, 150000},
        );
        expect(
          entries.map((e) => e.createdEventId).toSet(),
          {cashEventId, transferEventId},
        );

        final events = await db.select(db.events).get();
        expect(events, hasLength(3));
        expect(
          events.every((e) => e.applicationStatus == 'applied'),
          isTrue,
        );
        expect(
          events.every(
            (e) =>
                e.deliveryStatus ==
                (mode == AppMode.standalone ? 'not_required' : 'pending'),
          ),
          isTrue,
        );

        final cashPayload = MovimientoFinancieroRegistradoPayload.fromJson(
          (await persistence().eventById(cashEventId))!.payload,
        );
        expect(cashPayload.categoryEventId, catEventId);
        expect(cashPayload.direction, FinancialDirection.expense);

        final refs = await db.select(db.eventRefs).get();
        if (mode == AppMode.standalone) {
          expect(refs, isEmpty);
        } else {
          expect(refs, hasLength(5));
          expect(refs.every((r) => r.source == 'local_pending'), isTrue);
          expect(
            refs.where((r) => r.relationship == 'affects').length,
            3,
          );
          expect(
            refs.where(
              (r) =>
                  r.relationship == 'uses' &&
                  r.refType == 'financial_category' &&
                  r.refId == _rentaId,
            ),
            hasLength(2),
          );
        }

        // Registrar dinero no modifica la versión de la categoría.
        expect((await db.select(db.financialCategories).get()).single.version, 1);
      });

      test('reintento idéntico idempotente; contenido distinto se rechaza',
          () async {
        await useMode(mode);
        await catService().crear(rentaCommand());
        final first = await entryService().registrar(cashCommand());
        final retry = await entryService().registrar(cashCommand());
        expect(retry, first);
        expect(await db.select(db.financialEntries).get(), hasLength(1));
        expect(
          await db.select(db.events).get(),
          hasLength(2), // categoría + un solo registro
        );

        await expectLater(
          catService().crear(
            const CrearCategoriaFinancieraCommand(
              categoryId: _rentaId,
              name: 'Otra renta',
              direction: FinancialDirection.expense,
              nature: FinancialNature.operating,
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'Esta categoría ya se creó con otros datos.',
            ),
          ),
        );
        await expectLater(
          entryService().registrar(
            RegistrarMovimientoFinancieroCommand(
              entryId: _cashEntryId,
              categoryId: _rentaId,
              amountMinor: 99999,
              method: 'transfer',
              occurredAtMs: _cashAt,
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'Este registro ya se capturó con otros datos.',
            ),
          ),
        );
        expect(await db.select(db.financialEntries).get(), hasLength(1));
      });

      test('reintento compara el payload completo (contrato §6.2)', () async {
        await useMode(mode);
        await catService().crear(rentaCommand());
        final first = await entryService().registrar(cashCommand());
        final before = (await db.select(db.financialEntries).get()).single;

        const mismatch = 'Este registro ya se capturó con otros datos.';
        final rejected = throwsA(
          isA<StateError>().having((e) => e.message, 'message', mismatch),
        );

        // notes distinto con el resto idéntico.
        await expectLater(
          entryService().registrar(
            RegistrarMovimientoFinancieroCommand(
              entryId: _cashEntryId,
              categoryId: _rentaId,
              amountMinor: 50000,
              method: 'cash',
              occurredAtMs: _cashAt,
              notes: 'Otra nota',
            ),
          ),
          rejected,
        );

        // notes idéntico pero reference agregado.
        await expectLater(
          entryService().registrar(
            RegistrarMovimientoFinancieroCommand(
              entryId: _cashEntryId,
              categoryId: _rentaId,
              amountMinor: 50000,
              method: 'cash',
              occurredAtMs: _cashAt,
              notes: 'Renta en efectivo',
              reference: 'SPEI-2026-09-10',
            ),
          ),
          rejected,
        );

        // Divergencia de los snapshots derivados de la categoría: el reintento
        // compara también nombre, dirección y naturaleza.
        for (final divergence in <FinancialCategoriesCompanion>[
          FinancialCategoriesCompanion(name: const Value('Renta editada')),
          FinancialCategoriesCompanion(direction: const Value('in')),
          FinancialCategoriesCompanion(nature: const Value('capital')),
        ]) {
          await (db.update(db.financialCategories)
                ..where((t) => t.id.equals(_rentaId)))
              .write(divergence);
          await expectLater(
            entryService().registrar(cashCommand()),
            rejected,
          );
        }

        // El dinero registrado nunca se altera ni se duplica.
        final after = await db.select(db.financialEntries).get();
        expect(after, hasLength(1));
        expect(after.single.amountMinor, before.amountMinor);
        expect(after.single.notes, before.notes);
        expect(after.single.reference, before.reference);
        expect(after.single.createdEventId, first);
        expect(await db.select(db.events).get(), hasLength(2));
      });

      test('futuro rechazado y categoría inexistente rechazada', () async {
        await useMode(mode);
        await catService().crear(rentaCommand());
        await expectLater(
          entryService().registrar(
            RegistrarMovimientoFinancieroCommand(
              entryId: _futuroEntryId,
              categoryId: _rentaId,
              amountMinor: 1000,
              method: 'cash',
              occurredAtMs: _futuro,
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'La fecha del registro no puede ser futura.',
            ),
          ),
        );
        await expectLater(
          entryService().registrar(
            RegistrarMovimientoFinancieroCommand(
              entryId: _otroEntryId,
              categoryId: _ingresosVariosId,
              amountMinor: 1000,
              method: 'cash',
              occurredAtMs: _cashAt,
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'La categoría del registro no está disponible.',
            ),
          ),
        );
        expect(await db.select(db.financialEntries).get(), isEmpty);
      });

      test('rollback atómico: handler lanza tras aplicar', () async {
        await useMode(mode);
        await catService().crear(rentaCommand());
        final eventCount = (await db.select(db.events).get()).length;
        final refCount = (await db.select(db.eventRefs).get()).length;

        failAfterApply = true;
        await expectLater(
          entryService().registrar(cashCommand()),
          throwsStateError,
        );
        failAfterApply = false;

        expect(await db.select(db.events).get(), hasLength(eventCount));
        expect(await db.select(db.financialEntries).get(), isEmpty);
        expect(await db.select(db.eventRefs).get(), hasLength(refCount));
        expect(
          (await db.select(db.financialCategories).get()).single.version,
          1,
        );

        await entryService().registrar(cashCommand());
        expect(await db.select(db.events).get(), hasLength(eventCount + 1));
        expect(await db.select(db.financialEntries).get(), hasLength(1));
      });

      test('reinicio desde archivo conserva eventos, proyecciones y reporte',
          () async {
        await useMode(mode);
        await catService().crear(rentaCommand());
        await entryService().registrar(cashCommand());
        await entryService().registrar(transferCommand());

        await db.close();
        db = AppDatabase.forTesting(
          NativeDatabase(File('${directory.path}/test.sqlite')),
        );

        expect(await db.select(db.financialCategories).get(), hasLength(1));
        expect(await db.select(db.financialEntries).get(), hasLength(2));
        final events = await db.select(db.events).get();
        expect(events, hasLength(3));
        expect(
          events.every(
            (e) =>
                e.deliveryStatus ==
                (mode == AppMode.standalone ? 'not_required' : 'pending'),
          ),
          isTrue,
        );
        if (mode != AppMode.standalone) {
          expect(await db.select(db.eventRefs).get(), hasLength(5));
        }

        final report = await FinancialEntryRepositoryImpl(db)
            .watchFinancialReport(fromMs: _fromSep, toMs: _toOct)
            .first;
        expect(report.entries, hasLength(2));
        expect(
          report.entries.map((e) => e.id).toList(),
          [_transferEntryId, _cashEntryId],
        );
        expect(report.expenseMinor, BigInt.from(200000));
        expect(report.cashMinor, BigInt.from(50000));
        expect(report.transferMinor, BigInt.from(150000));
        expect(report.incomeMinor, BigInt.zero);
        expect(report.netMinor, BigInt.from(-200000));
      });

      test('incidencia de entrega conserva el registro visible en el reporte',
          () async {
        await useMode(mode);
        await catService().crear(rentaCommand());
        final cashEventId = await entryService().registrar(cashCommand());
        await persistence().updateEventSyncStatus(
          cashEventId,
          'rejected',
          rejectionReason: 'Incidencia de entrega',
        );

        final report = await FinancialEntryRepositoryImpl(db)
            .watchFinancialReport(fromMs: _fromSep, toMs: _toOct)
            .first;
        final entry = report.entries.single;
        expect(entry.amountMinor, 50000);
        expect(entry.deliveryStatus, 'rejected');
        expect(entry.rejectionReason, 'Incidencia de entrega');
        expect(report.expenseMinor, BigInt.from(50000));
      });
    });
  }

  group('handlers idempotentes', () {
    SyncEvent categoryEvent({
      String eventId = _rentaEventId,
      int? serverSequence,
      int? baseVersion = 1,
      int? baseServerSequence,
      String name = 'Renta',
      String direction = 'out',
      String nature = 'operating',
      String? aggregateType,
      String? eventType,
    }) =>
        SyncEvent(
          eventId: eventId,
          aggregateType:
              aggregateType ?? CategoriaFinancieraCreadaPayload.aggregateType,
          aggregateId: _rentaId,
          eventType: eventType ?? CategoriaFinancieraCreadaPayload.eventType,
          deviceId: 'tablet',
          userId: 'user',
          createdAtLocal: DateTime.now().toUtc(),
          baseVersion: baseVersion,
          baseServerSequence: baseServerSequence,
          serverSequence: serverSequence,
          payload: {'name': name, 'direction': direction, 'nature': nature},
        );

    SyncEvent entryEvent({
      required String eventId,
      required String aggregateId,
      Map<String, Object?>? payload,
      int? serverSequence,
      int? baseVersion = 1,
      int? baseServerSequence,
      String? aggregateType,
      String? eventType,
    }) =>
        SyncEvent(
          eventId: eventId,
          aggregateType:
              aggregateType ?? MovimientoFinancieroRegistradoPayload.aggregateType,
          aggregateId: aggregateId,
          eventType:
              eventType ?? MovimientoFinancieroRegistradoPayload.eventType,
          deviceId: 'tablet',
          userId: 'user',
          createdAtLocal: DateTime.now().toUtc(),
          baseVersion: baseVersion,
          baseServerSequence: baseServerSequence,
          serverSequence: serverSequence,
          payload:
              payload ??
              readFinancialFixture('registro/entry-renta-cash-valid.json'),
        );

    test('ecos no duplican ni cambian versión/importe', () async {
      await FinancialCategoryEventHandler(catStore()).apply(categoryEvent());
      final handler = FinancialEntryEventHandler(entryStore(), catStore());
      await handler.apply(
        entryEvent(eventId: _cashEventId, aggregateId: _cashEntryId),
      );
      await handler.apply(
        entryEvent(
          eventId: _cashEventId,
          aggregateId: _cashEntryId,
          serverSequence: 40,
        ),
      );

      final rows = await db.select(db.financialEntries).get();
      expect(rows, hasLength(1));
      expect(rows.single.lastServerSequence, 40);
      expect(rows.single.version, 1);
      expect(rows.single.amountMinor, 50000);

      await FinancialCategoryEventHandler(
        catStore(),
      ).apply(categoryEvent(serverSequence: 12));
      final category = (await db.select(db.financialCategories).get()).single;
      expect(category.lastServerSequence, 12);
      expect(category.version, 1);
      expect(category.name, 'Renta');
    });

    test('colisión de identidad no sobrescribe', () async {
      await FinancialCategoryEventHandler(catStore()).apply(categoryEvent());
      final handler = FinancialEntryEventHandler(entryStore(), catStore());
      await handler.apply(
        entryEvent(eventId: _cashEventId, aggregateId: _cashEntryId),
      );

      await expectLater(
        handler.apply(
          entryEvent(eventId: _transferEventId, aggregateId: _cashEntryId),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Identidad de registro financiero ya registrada.',
          ),
        ),
      );
      await expectLater(
        FinancialCategoryEventHandler(catStore()).apply(
          categoryEvent(eventId: _cashEventId),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Ya existe una categoría financiera con id $_rentaId.',
          ),
        ),
      );
      expect(await db.select(db.financialEntries).get(), hasLength(1));
      expect((await db.select(db.financialCategories).get()).single.name, 'Renta');
    });

    test('desajuste de clasificación y dependencia inexistente', () async {
      await FinancialCategoryEventHandler(catStore()).apply(categoryEvent());
      final handler = FinancialEntryEventHandler(entryStore(), catStore());
      final snapshotMismatch = throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'La clasificación del registro no coincide con la categoría oficial.',
        ),
      );

      await expectLater(
        handler.apply(
          entryEvent(
            eventId: _transferEventId,
            aggregateId: _transferEntryId,
            payload: readFinancialFixture(
              'registro/entry-direction-snapshot-invalid.json',
            ),
          ),
        ),
        snapshotMismatch,
      );
      await expectLater(
        handler.apply(
          entryEvent(
            eventId: _cashEventId,
            aggregateId: _cashEntryId,
            payload: readFinancialFixture(
              'registro/entry-nature-snapshot-invalid.json',
            ),
          ),
        ),
        snapshotMismatch,
      );
      await expectLater(
        handler.apply(
          entryEvent(
            eventId: _ingresoEventId,
            aggregateId: _ingresoEntryId,
            payload: readFinancialFixture(
              'registro/entry-dependencia-inexistente.json',
            ),
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'La categoría del registro no está disponible.',
          ),
        ),
      );
      expect(await db.select(db.financialEntries).get(), isEmpty);
    });

    test('sobres inválidos rechazados (pares del contrato §6.1)', () async {
      final handler = FinancialEntryEventHandler(entryStore(), catStore());
      for (final sobre in [
        entryEvent(
          eventId: _cashEventId,
          aggregateId: _cashEntryId,
          aggregateType: 'financial_category',
        ),
        entryEvent(
          eventId: _cashEventId,
          aggregateId: _cashEntryId,
          eventType: 'otro_evento',
        ),
        entryEvent(
          eventId: _cashEventId,
          aggregateId: _cashEntryId,
          baseVersion: 2,
        ),
        entryEvent(
          eventId: _cashEventId,
          aggregateId: _cashEntryId,
          baseServerSequence: 5,
        ),
      ]) {
        await expectLater(
          handler.apply(sobre),
          throwsA(isA<FormatException>()),
        );
      }
      for (final sobre in [
        categoryEvent(aggregateType: 'financial_entry'),
        categoryEvent(baseVersion: 2),
        categoryEvent(baseServerSequence: 5),
      ]) {
        await expectLater(
          FinancialCategoryEventHandler(catStore()).apply(sobre),
          throwsA(isA<FormatException>()),
        );
      }
      expect(await db.select(db.financialEntries).get(), isEmpty);
      expect(await db.select(db.financialCategories).get(), isEmpty);
    });

    test('el oficial reemplaza la alta local por upsert sin borrar', () async {
      await FinancialCategoryEventHandler(catStore()).apply(categoryEvent());
      await FinancialCategoryEventHandler(catStore()).apply(
        categoryEvent(eventId: _cashEventId, name: 'Renta oficial', serverSequence: 7),
      );
      final category = (await db.select(db.financialCategories).get()).single;
      expect(category.name, 'Renta oficial');
      expect(category.createdEventId, _cashEventId);
      expect(category.lastServerSequence, 7);
      expect(category.version, 1);
      expect(await db.select(db.financialCategories).get(), hasLength(1));
    });
  });

  group('informe financiero (§8.1)', () {
    test('dataset septiembre: totales BigInt, bordes [from, to) y orden',
        () async {
      await seedCategory(
        id: _rentaId,
        eventId: _rentaEventId,
        name: 'Renta',
        direction: 'out',
        nature: 'operating',
      );
      await seedCategory(
        id: _ingresosVariosId,
        eventId: _ingresosVariosEventId,
        name: 'Ingresos varios',
        direction: 'in',
        nature: 'operating',
      );
      await seedEntry(
        id: _cashEntryId,
        eventId: _cashEventId,
        categoryId: _rentaId,
        categoryNameSnapshot: 'Renta',
        direction: 'out',
        nature: 'operating',
        amountMinor: 50000,
        method: 'cash',
        occurredAtMs: _cashAt,
        notes: 'Renta en efectivo',
      );
      await seedEntry(
        id: _ingresoEntryId,
        eventId: _ingresoEventId,
        categoryId: _ingresosVariosId,
        categoryNameSnapshot: 'Ingresos varios',
        direction: 'in',
        nature: 'operating',
        amountMinor: 200000,
        method: 'cash',
        occurredAtMs: _ingresoAt,
        notes: 'Ingreso operativo de la semana',
      );
      await seedEntry(
        id: _transferEntryId,
        eventId: _transferEventId,
        categoryId: _rentaId,
        categoryNameSnapshot: 'Renta',
        direction: 'out',
        nature: 'operating',
        amountMinor: 150000,
        method: 'transfer',
        occurredAtMs: _transferAt,
        notes: 'Renta de septiembre',
        reference: 'SPEI-2026-09-20',
      );
      // Bordes: exactamente en to_ms (excluido) y en from_ms - 1 (excluido).
      await seedEntry(
        id: _bordeToEntryId,
        eventId: _bordeToEventId,
        categoryId: _rentaId,
        categoryNameSnapshot: 'Renta',
        direction: 'out',
        nature: 'operating',
        amountMinor: 12345,
        method: 'cash',
        occurredAtMs: _toOct,
      );
      await seedEntry(
        id: _bordeAntesEntryId,
        eventId: _bordeAntesEventId,
        categoryId: _rentaId,
        categoryNameSnapshot: 'Renta',
        direction: 'out',
        nature: 'operating',
        amountMinor: 67890,
        method: 'cash',
        occurredAtMs: _fromSep - 1,
      );

      final report = await FinancialEntryRepositoryImpl(db)
          .watchFinancialReport(fromMs: _fromSep, toMs: _toOct)
          .first;

      expect(
        report.entries.map((e) => e.id).toList(),
        [_transferEntryId, _ingresoEntryId, _cashEntryId],
      );
      expect(report.incomeMinor, BigInt.from(200000));
      expect(report.expenseMinor, BigInt.from(200000));
      expect(report.cashMinor, BigInt.from(250000));
      expect(report.transferMinor, BigInt.from(150000));
      expect(report.netMinor, BigInt.zero);
    });

    test('filtros method, direction y categoryId', () async {
      await seedCategory(
        id: _rentaId,
        eventId: _rentaEventId,
        name: 'Renta',
        direction: 'out',
        nature: 'operating',
      );
      await seedCategory(
        id: _ingresosVariosId,
        eventId: _ingresosVariosEventId,
        name: 'Ingresos varios',
        direction: 'in',
        nature: 'operating',
      );
      await seedEntry(
        id: _cashEntryId,
        eventId: _cashEventId,
        categoryId: _rentaId,
        categoryNameSnapshot: 'Renta',
        direction: 'out',
        nature: 'operating',
        amountMinor: 50000,
        method: 'cash',
        occurredAtMs: _cashAt,
      );
      await seedEntry(
        id: _ingresoEntryId,
        eventId: _ingresoEventId,
        categoryId: _ingresosVariosId,
        categoryNameSnapshot: 'Ingresos varios',
        direction: 'in',
        nature: 'operating',
        amountMinor: 200000,
        method: 'cash',
        occurredAtMs: _ingresoAt,
      );
      await seedEntry(
        id: _transferEntryId,
        eventId: _transferEventId,
        categoryId: _rentaId,
        categoryNameSnapshot: 'Renta',
        direction: 'out',
        nature: 'operating',
        amountMinor: 150000,
        method: 'transfer',
        occurredAtMs: _transferAt,
      );

      final repo = FinancialEntryRepositoryImpl(db);
      final cashOnly = await repo.watchFinancialReport(
        fromMs: _fromSep,
        toMs: _toOct,
        method: 'cash',
      ).first;
      expect(cashOnly.entries, hasLength(2));
      expect(cashOnly.cashMinor, BigInt.from(250000));
      expect(cashOnly.transferMinor, BigInt.zero);

      final expenses = await repo.watchFinancialReport(
        fromMs: _fromSep,
        toMs: _toOct,
        direction: 'out',
      ).first;
      expect(expenses.entries, hasLength(2));
      expect(expenses.expenseMinor, BigInt.from(200000));
      expect(expenses.incomeMinor, BigInt.zero);

      final renta = await repo.watchFinancialReport(
        fromMs: _fromSep,
        toMs: _toOct,
        categoryId: _rentaId,
      ).first;
      expect(renta.entries, hasLength(2));
      expect(renta.expenseMinor, BigInt.from(200000));
      expect(renta.incomeMinor, BigInt.zero);
    });

    test('límites [from, to): inclusivo en from, exclusivo en to', () async {
      await seedCategory(
        id: _rentaId,
        eventId: _rentaEventId,
        name: 'Renta',
        direction: 'out',
        nature: 'operating',
      );
      await seedEntry(
        id: _bordeToEntryId,
        eventId: _bordeToEventId,
        categoryId: _rentaId,
        categoryNameSnapshot: 'Renta',
        direction: 'out',
        nature: 'operating',
        amountMinor: 1000,
        method: 'cash',
        occurredAtMs: _toOct, // excluido: exactamente to_ms
      );
      await seedEntry(
        id: _bordeAntesEntryId,
        eventId: _bordeAntesEventId,
        categoryId: _rentaId,
        categoryNameSnapshot: 'Renta',
        direction: 'out',
        nature: 'operating',
        amountMinor: 2000,
        method: 'cash',
        occurredAtMs: _toOct - 1, // incluido: to_ms - 1
      );
      await seedEntry(
        id: '99999999-9999-4999-8999-999999999901',
        eventId: '99999999-9999-4999-8999-999999999902',
        categoryId: _rentaId,
        categoryNameSnapshot: 'Renta',
        direction: 'out',
        nature: 'operating',
        amountMinor: 3000,
        method: 'cash',
        occurredAtMs: _fromSep - 1, // excluido: from_ms - 1
      );
      await seedEntry(
        id: '99999999-9999-4999-8999-999999999903',
        eventId: '99999999-9999-4999-8999-999999999904',
        categoryId: _rentaId,
        categoryNameSnapshot: 'Renta',
        direction: 'out',
        nature: 'operating',
        amountMinor: 4000,
        method: 'cash',
        occurredAtMs: _fromSep, // incluido: exactamente from_ms
      );

      final report = await FinancialEntryRepositoryImpl(db)
          .watchFinancialReport(fromMs: _fromSep, toMs: _toOct)
          .first;
      expect(
        report.entries.map((e) => e.id).toSet(),
        {
          _bordeAntesEntryId,
          '99999999-9999-4999-8999-999999999903',
        },
      );
      expect(report.cashMinor, BigInt.from(6000));
    });
  });
}