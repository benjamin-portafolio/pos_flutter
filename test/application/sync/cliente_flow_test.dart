import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_flutter/application/commands/clientes/editar_cliente_command.dart';
import 'package:pos_flutter/application/sync/payloads/cliente_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/remote_event_preparer.dart';
import 'package:pos_flutter/application/sync/categoria_eliminada_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/sync_push_service.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
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
        ClienteActualizadoPayload.eventType: ClienteEventHandler(
          projection,
        ).applyUpdate,
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
      clienteProjectionStore: projection,
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
      remoteEventPreparer: RemoteEventPreparer(
        syncPersistence: persistence,
        categoriaEliminadaConflictProjectionRestorer:
            CategoriaEliminadaConflictProjectionRestorer(categories),
        conflictProjectionCleaner: cleaner,
      ),
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

  Future<SyncEvent> edit(String id, String name, {String? phone}) async {
    final row = (await projection.findById(id))!;
    await command.editarCliente(
      EditarClienteCommand(
        clienteId: id,
        baseEventId: row.lastEventId!,
        nombre: name,
        telefono: phone,
      ),
    );
    final saved = (await db.select(db.events).get()).last;
    return SyncEvent(
      eventId: saved.eventId,
      aggregateType: saved.aggregateType,
      aggregateId: saved.aggregateId,
      eventType: saved.eventType,
      deviceId: saved.deviceId,
      userId: saved.userId,
      createdAtLocal: saved.createdAtLocal,
      baseVersion: saved.baseVersion,
      baseServerSequence: saved.baseServerSequence,
      payload: Map<String, Object?>.from(jsonDecode(saved.payload) as Map),
    );
  }

  for (final mode in AppMode.values) {
    test(
      'edición normaliza, conserva identidad y valida base en ${mode.name}',
      () async {
        config.update(AppConfig.initial.copyWith(mode: mode));
        await command.crearCliente(
          const CrearClienteCommand(nombre: 'Ana', telefono: '555'),
        );
        final before = (await db.select(db.clientes).get()).single;
        final update = await edit(before.id, ' Ana María ', phone: '  ');
        await ClienteEventHandler(projection).applyUpdate(update);
        final after = (await db.select(db.clientes).get()).single;
        expect(after.nombre, 'Ana María');
        expect(after.telefono, isNull);
        expect(after.id, before.id);
        expect(after.createdEventId, before.createdEventId);
        expect(after.version, 2);
        expect(after.lastEventId, update.eventId);
        expect(
          (await db.select(db.events).get()).last.deliveryStatus,
          mode == AppMode.standalone ? 'not_required' : 'pending',
        );
        expect(
          await db.select(db.eventRefs).get(),
          hasLength(mode == AppMode.standalone ? 0 : 2),
        );
        await edit(before.id, 'Ana María');
        expect(await db.select(db.events).get(), hasLength(2));
        await expectLater(edit(before.id, '  '), throwsFormatException);
        await expectLater(
          command.editarCliente(
            EditarClienteCommand(
              clienteId: before.id,
              baseEventId: before.lastEventId!,
              nombre: 'Viejo',
            ),
          ),
          throwsStateError,
        );
        expect(await db.select(db.events).get(), hasLength(2));
      },
    );
  }
  test(
    'eco de alta y edición conserva la siguiente edición optimista',
    () async {
      final creation = _event('created', 'customer');
      await local.appendAndApply(creation, refs: _refs(creation));
      final first = await edit('customer', 'Primero');
      final second = await edit('customer', 'Segundo');
      await remote.applySyncedEvents([
        creation.copyWith(serverSequence: 10),
        first.copyWith(serverSequence: 11),
      ]);
      final current = (await projection.findById('customer'))!;
      expect(current.nombre, 'Segundo');
      expect(current.version, 3);
      expect(current.lastEventId, second.eventId);
      expect(current.lastServerSequence, 11);
      expect((await revalidator.revalidatePendingEvents()).conflicts, 0);
    },
  );
  test(
    'pull concurrente restaura cadena local y aplica ganador oficial',
    () async {
      final creation = _event(
        'created',
        'customer',
      ).copyWith(serverSequence: 10);
      await remote.applySyncedEvents([creation]);
      final first = await edit('customer', 'Primero');
      final second = await edit('customer', 'Segundo');
      final official = first.copyWith(
        eventId: 'remote-edit',
        serverSequence: 11,
        payload: ClienteActualizadoPayload(
          baseEventId: 'created',
          before: const ClienteCreadoPayload(nombre: 'Ana'),
          after: const ClienteCreadoPayload(nombre: 'Oficial', telefono: '001'),
        ).toJson(),
      );
      await remote.applySyncedEvents([official]);
      await remote.applySyncedEvents([official]);
      final current = (await projection.findById('customer'))!;
      expect(current.nombre, 'Oficial');
      expect(current.telefono, '001');
      expect(current.version, 2);
      for (final event in [first, second]) {
        expect(
          (await db.eventDao.obtenerEventoPorId(event.eventId))!.deliveryStatus,
          'conflict',
        );
        await cleaner.hideConflictProjection(event);
      }
      expect((await projection.findById('customer'))!.nombre, 'Oficial');
    },
  );
  test(
    'push espera alta y edición anterior; conflicto restaura toda la cadena',
    () async {
      final creation = _event('created', 'customer');
      await local.appendAndApply(creation, refs: _refs(creation));
      final first = await edit('customer', 'Primero');
      await edit('customer', 'Segundo');
      final requests = <List<dynamic>>[];
      final push = SyncPushService(
        syncPersistence: DriftSyncPersistence(
          db: db,
          eventDao: db.eventDao,
          eventRefDao: db.eventRefDao,
          syncCheckpointDao: db.syncCheckpointDao,
        ),
        endpointConfig: SyncEndpointConfig(
          initialBaseUrl: 'http://localhost:3000',
        ),
        conflictProjectionCleaner: cleaner,
        client: MockClient((request) async {
          final events = (jsonDecode(request.body) as Map)['events'] as List;
          requests.add(events);
          return http.Response(
            jsonEncode({
              'results': events
                  .map(
                    (e) => {
                      'event_id': e['event_id'],
                      'status': requests.length == 1 ? 'accepted' : 'conflict',
                      'server_sequence': requests.length,
                      'created_at_server': DateTime(2026).toIso8601String(),
                    },
                  )
                  .toList(),
            }),
            200,
          );
        }),
      );
      await push.pushPendingEvents();
      expect(requests.single.single['event_id'], creation.eventId);
      await push.pushPendingEvents();
      expect(requests.last.single['event_id'], first.eventId);
      expect((await projection.findById('customer'))!.nombre, 'Ana');
      expect((await projection.findById('customer'))!.version, 1);
    },
  );
  test('contrato edición normaliza y rechaza estructura inválida', () {
    final json = {
      'base_event_id': 'base',
      'before': {'nombre': ' Ana ', 'telefono': ' 001 '},
      'after': {'nombre': ' Nueva ', 'telefono': ' '},
    };
    final payload = ClienteActualizadoPayload.fromJson(json);
    expect(
      ClienteActualizadoPayload.fromJson(payload.toJson()).after.nombre,
      'Nueva',
    );
    expect(payload.after.telefono, isNull);
    for (final invalid in [
      {...json, 'base_event_id': ''},
      {...json, 'before': null},
      {
        ...json,
        'after': {'nombre': ' '},
      },
    ]) {
      expect(
        () => ClienteActualizadoPayload.fromJson(invalid),
        throwsFormatException,
      );
    }
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
