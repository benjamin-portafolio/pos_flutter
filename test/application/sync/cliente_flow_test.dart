import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/clientes/cliente_command_service.dart';
import 'package:pos_flutter/application/commands/clientes/crear_cliente_command.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/categoria_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/categoria_movida_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/cliente_event_handler.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/cliente_creado_payload.dart';
import 'package:pos_flutter/application/sync/pending_event_revalidator.dart';
import 'package:pos_flutter/application/sync/remote_event_applier.dart';
import 'package:pos_flutter/application/sync/server_echo_acknowledger.dart';
import 'package:pos_flutter/application/sync/sync_conflict_projection_cleaner.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_cliente_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_espacio_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';
import 'package:pos_flutter/data/local/drift/drift_synced_event_store.dart';
import 'package:pos_flutter/data/repositories/cliente_repository_impl.dart';

void main() {
  late AppDatabase db;
  late AppConfigController config;
  late DriftClienteProjectionStore projection;
  late DriftLocalEventStore local;
  late ClienteCommandService command;
  late RemoteEventApplier remote;
  late PendingEventRevalidator revalidator;
  late SyncConflictProjectionCleaner cleaner;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    config = AppConfigController(
      AppConfig.initial.copyWith(mode: AppMode.serverSync),
    );
    projection = DriftClienteProjectionStore(db.clienteDao);
    final categories = DriftCategoriaProjectionStore(
      categoriaDao: db.categoriaDao,
    );
    final spaces = DriftEspacioProjectionStore(espacioDao: db.espacioDao);
    final restore = CategoriaConflictProjectionRestorer(categories);
    final moved = CategoriaMovidaConflictProjectionRestorer(categories);
    final processor = EventProcessor(
      handlers: {
        ClienteCreadoPayload.eventType: ClienteEventHandler(projection).apply,
      },
    );
    local = DriftLocalEventStore(
      db: db,
      eventDao: db.eventDao,
      eventRefDao: db.eventRefDao,
      eventProcessor: processor,
      appConfigController: config,
    );
    command = ClienteCommandService(
      eventStore: local,
      commandContext: const LocalCommandContext(
        deviceId: 'tablet',
        userId: 'user',
      ),
    );
    final persistence = DriftSyncPersistence(
      db: db,
      eventDao: db.eventDao,
      eventRefDao: db.eventRefDao,
      syncCheckpointDao: db.syncCheckpointDao,
    );
    revalidator = PendingEventRevalidator(
      syncPersistence: persistence,
      syncedEventHistory: persistence,
      espacioProjectionStore: spaces,
      categoriaProjectionStore: categories,
      clienteProjectionStore: projection,
      categoriaConflictProjectionRestorer: restore,
      categoriaMovidaConflictProjectionRestorer: moved,
    );
    cleaner = SyncConflictProjectionCleaner(
      espacioProjectionStore: spaces,
      categoriaProjectionStore: categories,
      clienteProjectionStore: projection,
      categoriaConflictProjectionRestorer: restore,
      categoriaMovidaConflictProjectionRestorer: moved,
    );
    remote = RemoteEventApplier(
      eventStore: DriftSyncedEventStore(db: db),
      eventProcessor: processor,
      serverEchoAcknowledger: ServerEchoAcknowledger(
        categoriaProjectionStore: categories,
        clienteProjectionStore: projection,
      ),
    );
  });
  tearDown(() async {
    config.dispose();
    await db.close();
  });

  for (final mode in AppMode.values) {
    test('alta normalizada, metadatos y referencias en ${mode.name}', () async {
      config.update(AppConfig.initial.copyWith(mode: mode));
      await command.crearCliente(
        const CrearClienteCommand(nombre: ' Ana ', telefono: ' 00123 '),
      );
      final row = (await db.select(db.clientes).get()).single;
      final event = (await db.select(db.events).get()).single;
      expect(row.nombre, 'Ana');
      expect(row.telefono, '00123');
      expect(row.version, 1);
      expect(row.createdEventId, event.eventId);
      expect(row.lastEventId, event.eventId);
      expect(row.lastServerSequence, isNull);
      expect(event.applicationStatus, 'applied');
      expect(
        event.deliveryStatus,
        mode == AppMode.standalone ? 'not_required' : 'pending',
      );
      final refs = await db.select(db.eventRefs).get();
      if (mode == AppMode.standalone) {
        expect(refs, isEmpty);
      } else {
        expect(refs.single.refType, 'cliente');
        expect(refs.single.refId, row.id);
        expect(refs.single.relationship, 'affects');
        expect(refs.single.source, 'local_pending');
      }
      final clients = await ClienteRepositoryImpl(
        db.clienteDao,
      ).watchClientes().first;
      expect(clients.single.nombre, 'Ana');
    });
    test('rechaza nombre vacío sin guardar nada en ${mode.name}', () async {
      config.update(AppConfig.initial.copyWith(mode: mode));
      await expectLater(
        command.crearCliente(const CrearClienteCommand(nombre: '   ')),
        throwsFormatException,
      );
      expect(await db.select(db.events).get(), isEmpty);
      expect(await db.select(db.eventRefs).get(), isEmpty);
      expect(await db.select(db.clientes).get(), isEmpty);
    });
  }
  test('solo nombre y datos repetidos son válidos', () async {
    await command.crearCliente(
      const CrearClienteCommand(nombre: 'Ana', telefono: '  '),
    );
    await command.crearCliente(const CrearClienteCommand(nombre: 'Ana'));
    final rows = await db.select(db.clientes).get();
    expect(rows, hasLength(2));
    expect(rows.every((r) => r.telefono == null), isTrue);
    expect(rows[0].id, isNot(rows[1].id));
  });
  test(
    'repetir evento es idempotente y otro alta con mismo id revierte toda la transacción',
    () async {
      final event = _event('one', 'customer');
      await local.appendAndApply(event, refs: _refs(event));
      await ClienteEventHandler(projection).apply(event);
      expect(await db.select(db.clientes).get(), hasLength(1));
      final other = _event('two', 'customer');
      await expectLater(
        local.appendAndApply(other, refs: _refs(other)),
        throwsStateError,
      );
      expect(await db.select(db.events).get(), hasLength(1));
      expect(await db.select(db.eventRefs).get(), hasLength(1));
    },
  );
  test(
    'eco confirma evento y secuencia sin duplicar o sobrescribir datos',
    () async {
      final event = _event('one', 'customer');
      await local.appendAndApply(event, refs: _refs(event));
      final official = event.copyWith(
        serverSequence: 10,
        createdAtServer: DateTime(2026),
        deliveryStatus: 'delivered',
        payload: {'nombre': 'No reemplazar', 'telefono': null},
      );
      await remote.applySyncedEvents([official]);
      await remote.applySyncedEvents([official.copyWith(serverSequence: 8)]);
      final row = (await db.select(db.clientes).get()).single;
      expect(row.nombre, 'Ana');
      expect(row.lastServerSequence, 10);
      expect(row.version, 1);
      expect(row.lastEventId, 'one');
      expect(
        (await db.select(db.events).get()).single.deliveryStatus,
        'delivered',
      );
      expect((await db.select(db.eventRefs).get()).single.source, 'server');
    },
  );
  test(
    'pull nuevo es idempotente y revierte la página y checkpoint si hay payload inválido',
    () async {
      final official = _event('one', 'customer').copyWith(serverSequence: 10);
      await remote.applySyncedEvents([official]);
      await remote.applySyncedEvents([official]);
      expect(await db.select(db.clientes).get(), hasLength(1));
      var checkpointAdvanced = false;
      await expectLater(
        remote.applySyncedEvents(
          [
            _event('two', 'second').copyWith(serverSequence: 11),
            _event(
              'three',
              'third',
            ).copyWith(serverSequence: 12, payload: {'nombre': ' '}),
          ],
          afterApply: () async {
            checkpointAdvanced = true;
          },
        ),
        throwsFormatException,
      );
      expect(checkpointAdvanced, isFalse);
      expect(await db.select(db.clientes).get(), hasLength(1));
      expect(await db.select(db.events).get(), hasLength(1));
    },
  );
  test(
    'preflight oficial reemplaza alta pendiente y revalidación conserva ganador',
    () async {
      final pending = _event('local', 'customer');
      await local.appendAndApply(pending, refs: _refs(pending));
      await remote.applySyncedEvents(
        [
          _event('official', 'customer').copyWith(
            serverSequence: 1,
            payload: {'nombre': 'Ganador', 'telefono': null},
          ),
        ],
        afterApply: () async {
          await revalidator.revalidatePendingEvents();
        },
      );
      final row = (await db.select(db.clientes).get()).single;
      expect(row.nombre, 'Ganador');
      expect(row.createdEventId, 'official');
      expect(
        (await db.eventDao.obtenerEventoPorId('local'))!.deliveryStatus,
        'conflict',
      );
      await cleaner.hideConflictProjection(pending);
      expect(await db.select(db.clientes).get(), hasLength(1));
    },
  );
  test(
    'conflicto reportado por push retira únicamente la proyección perdedora',
    () async {
      final pending = _event('local', 'customer');
      await local.appendAndApply(pending, refs: _refs(pending));
      await cleaner.hideConflictProjection(pending);
      expect(await db.select(db.clientes).get(), isEmpty);
      expect(await db.select(db.events).get(), hasLength(1));
    },
  );
  test('payload conserva teléfono textual y rechaza tipos inválidos', () {
    expect(
      ClienteCreadoPayload.fromJson({
        'nombre': ' Ana ',
        'telefono': ' +52 001 ',
      }).toJson(),
      {'nombre': 'Ana', 'telefono': '+52 001'},
    );
    for (final name in [null, '', '  ', 42]) {
      expect(
        () => ClienteCreadoPayload.fromJson({'nombre': name}),
        throwsFormatException,
      );
    }
    expect(
      () => ClienteCreadoPayload.fromJson({'nombre': 'Ana', 'telefono': 123}),
      throwsFormatException,
    );
    expect(
      ClienteCreadoPayload.fromJson({'nombre': 'Ana', 'extra': true}).telefono,
      isNull,
    );
  });
}

SyncEvent _event(String eventId, String id) => SyncEvent(
  eventId: eventId,
  aggregateType: ClienteCreadoPayload.aggregateType,
  aggregateId: id,
  eventType: ClienteCreadoPayload.eventType,
  deviceId: 'tablet',
  userId: 'user',
  baseVersion: 1,
  createdAtLocal: DateTime(2026),
  payload: {'nombre': 'Ana', 'telefono': null},
);
List<LocalEventRef> _refs(SyncEvent event) => [
  LocalEventRef.affects(refType: 'cliente', refId: event.aggregateId),
];
