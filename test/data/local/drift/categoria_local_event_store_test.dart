import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/categoria_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/categoria_event_registry.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';

void main() {
  late AppDatabase db;
  late CategoriaDao categoriaDao;
  late EventDao eventDao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    categoriaDao = CategoriaDao(db);
    eventDao = EventDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('server_sync guarda categoria, evento y event_ref pendiente', () async {
    final store = _store(AppMode.serverSync, db, categoriaDao, eventDao);

    await store.appendAndApply(
      _event(),
      refs: const [
        LocalEventRef.affects(refType: 'category', refId: 'category_1'),
      ],
    );

    final categoria = await categoriaDao.obtenerCategoriaPorId('category_1');
    final event = (await eventDao.obtenerEventosPendientes()).single;
    final ref = (await db.select(db.eventRefs).get()).single;
    expect(categoria?.name, 'Bebidas');
    expect(event.deliveryStatus, 'pending');
    expect(ref.refType, 'category');
    expect(ref.source, 'local_pending');
  });

  test('standalone aplica categoria sin persistir event_refs', () async {
    final store = _store(AppMode.standalone, db, categoriaDao, eventDao);

    await store.appendAndApply(
      _event(),
      refs: const [
        LocalEventRef.affects(refType: 'category', refId: 'category_1'),
      ],
    );

    final categoria = await categoriaDao.obtenerCategoriaPorId('category_1');
    final event = (await db.select(db.events).get()).single;
    final refs = await db.select(db.eventRefs).get();
    expect(categoria?.name, 'Bebidas');
    expect(event.deliveryStatus, 'not_required');
    expect(refs, isEmpty);
  });

  test('server_sync aplica edición y conserva el evento pendiente', () async {
    final store = _store(AppMode.serverSync, db, categoriaDao, eventDao);
    const refs = [
      LocalEventRef.affects(refType: 'category', refId: 'category_1'),
    ];

    await store.appendAndApply(_event(), refs: refs);
    await store.appendAndApply(_updatedEvent(), refs: refs);

    final categoria = await categoriaDao.obtenerCategoriaPorId('category_1');
    final events = await eventDao.obtenerEventosPendientes();
    final storedRefs = await db.select(db.eventRefs).get();
    expect(categoria?.name, 'Bebidas frías');
    expect(categoria?.version, 2);
    expect(events.map((event) => event.eventType), [
      'categoria_creada',
      'categoria_actualizada',
    ]);
    expect(storedRefs, hasLength(2));
  });

  test('standalone aplica edición sin persistir event_refs', () async {
    final store = _store(AppMode.standalone, db, categoriaDao, eventDao);
    const refs = [
      LocalEventRef.affects(refType: 'category', refId: 'category_1'),
    ];

    await store.appendAndApply(_event(), refs: refs);
    await store.appendAndApply(_updatedEvent(), refs: refs);

    final categoria = await categoriaDao.obtenerCategoriaPorId('category_1');
    final events = await db.select(db.events).get();
    expect(categoria?.name, 'Bebidas frías');
    expect(categoria?.version, 2);
    expect(events.map((event) => event.deliveryStatus).toSet(), {
      'not_required',
    });
    expect(await db.select(db.eventRefs).get(), isEmpty);
  });

  for (final mode in [AppMode.serverSync, AppMode.standalone]) {
    test('${mode.name} intercambia dos categorías de forma atómica', () async {
      final store = _store(mode, db, categoriaDao, eventDao);
      await store.appendAndApply(
        _event(),
        refs: const [
          LocalEventRef.affects(refType: 'category', refId: 'category_1'),
        ],
      );
      await store.appendAndApply(
        _event(eventId: 'event_2', aggregateId: 'category_2', sortOrder: 1),
        refs: const [
          LocalEventRef.affects(refType: 'category', refId: 'category_2'),
        ],
      );

      await store.appendAndApply(
        _movedEvent(),
        refs: const [
          LocalEventRef.affects(refType: 'category', refId: 'category_2'),
          LocalEventRef.affects(refType: 'category', refId: 'category_1'),
        ],
      );

      final categories = await categoriaDao.obtenerCategorias();
      expect(categories.map((category) => category.id), [
        'category_2',
        'category_1',
      ]);
      expect(categories.map((category) => category.sortOrder), [0, 1]);
      final refs = await db.select(db.eventRefs).get();
      expect(refs, mode == AppMode.serverSync ? hasLength(4) : isEmpty);
      final move = await (db.select(
        db.events,
      )..where((event) => event.eventId.equals('event_3'))).getSingle();
      expect(
        move.deliveryStatus,
        mode == AppMode.serverSync ? 'pending' : 'not_required',
      );
    });
  }
}

DriftLocalEventStore _store(
  AppMode mode,
  AppDatabase db,
  CategoriaDao categoriaDao,
  EventDao eventDao,
) {
  return DriftLocalEventStore(
    db: db,
    eventDao: eventDao,
    eventRefDao: EventRefDao(db),
    eventProcessor: EventProcessor(
      handlers: categoriaEventHandlers(
        CategoriaEventHandler(
          DriftCategoriaProjectionStore(categoriaDao: categoriaDao),
        ),
      ),
    ),
    appConfigController: AppConfigController(
      AppConfig.initial.copyWith(mode: mode, setupCompleted: true),
    ),
  );
}

SyncEvent _event({
  String eventId = 'event_1',
  String aggregateId = 'category_1',
  int sortOrder = 0,
}) {
  return SyncEvent(
    eventId: eventId,
    aggregateType: 'category',
    aggregateId: aggregateId,
    eventType: 'categoria_creada',
    deviceId: 'test_device',
    userId: 'test_user',
    baseVersion: 1,
    createdAtLocal: DateTime(2026),
    payload: {'name': 'Bebidas', 'color_key': 'cyan', 'sort_order': sortOrder},
  );
}

SyncEvent _movedEvent() {
  return SyncEvent(
    eventId: 'event_3',
    aggregateType: 'category',
    aggregateId: 'category_2',
    eventType: 'categoria_movida',
    deviceId: 'test_device',
    userId: 'test_user',
    baseVersion: 1,
    createdAtLocal: DateTime(2026, 1, 3),
    payload: const {
      'base_event_id': 'event_2',
      'changed_fields': ['sort_order'],
      'changes': {
        'sort_order': {'from': 1, 'to': 0},
      },
      'displaced_category': {
        'category_id': 'category_1',
        'base_event_id': 'event_1',
        'base_version': 1,
        'base_server_sequence': null,
        'sort_order': {'from': 0, 'to': 1},
      },
    },
  );
}

SyncEvent _updatedEvent() {
  return SyncEvent(
    eventId: 'event_2',
    aggregateType: 'category',
    aggregateId: 'category_1',
    eventType: 'categoria_actualizada',
    deviceId: 'test_device',
    userId: 'test_user',
    baseVersion: 1,
    createdAtLocal: DateTime(2026, 1, 2),
    payload: const {
      'base_event_id': 'event_1',
      'changed_fields': ['name'],
      'changes': {
        'name': {'from': 'Bebidas', 'to': 'Bebidas frías'},
      },
    },
  );
}
