import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/proveedores/crear_proveedor_command.dart';
import 'package:pos_flutter/application/commands/proveedores/editar_proveedor_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/projections/proveedor_projection.dart';
import 'package:pos_flutter/application/sync/payloads/proveedor_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/proveedor_creado_payload.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/application/sync/sync_availability_monitor.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/domain/proveedores/proveedor.dart';
import '../../../support/proveedor_harness.dart';

void main() {
  late ProveedorHarness h;
  setUp(() => h = ProveedorHarness());
  tearDown(() => h.dispose());

  Future<Proveedor> create() async {
    await h.service.crearProveedor(
      const CrearProveedorCommand(nombre: 'Norte'),
    );
    return (await h.repository.watchProveedores().first).single;
  }

  EditarProveedorCommand edit(Proveedor base, String name) =>
      EditarProveedorCommand(base: base, nombre: name);

  for (final name in ['', ' ', '\n\t']) {
    test(
      'nombre obligatorio [$name] sin escrituras en alta y edición',
      () async {
        await expectLater(
          h.service.crearProveedor(CrearProveedorCommand(nombre: name)),
          throwsFormatException,
        );
        expect(await h.events(), isEmpty);
        expect(await h.repository.watchProveedores().first, isEmpty);
        final base = await create();
        await expectLater(
          h.service.editarProveedor(edit(base, name)),
          throwsFormatException,
        );
        expect(await h.events(), hasLength(1));
        expect(
          (await h.repository.watchProveedores().first).single.nombre,
          'Norte',
        );
      },
    );
  }

  test(
    'normaliza y conserva teléfono como texto libre; permite nombres duplicados',
    () async {
      await h.service.crearProveedor(
        const CrearProveedorCommand(
          nombre: ' Norte ',
          telefono: ' 001 +52 ext. A ',
          notas: ' Entrega semanal \n',
        ),
      );
      final first = (await h.repository.watchProveedores().first).single;
      expect(first.nombre, 'Norte');
      expect(first.telefono, '001 +52 ext. A');
      expect(first.notas, 'Entrega semanal');
      await h.service.crearProveedor(
        const CrearProveedorCommand(
          nombre: 'Norte',
          telefono: '  ',
          notas: '\n',
        ),
      );
      final suppliers = await h.repository.watchProveedores().first;
      expect(suppliers, hasLength(2));
      expect(suppliers.map((s) => s.id).toSet(), hasLength(2));
      final second = suppliers.singleWhere((s) => s.id != first.id);
      expect(second.telefono, isNull);
      expect(second.notas, isNull);
      final update = EditarProveedorCommand(
        base: first,
        nombre: ' Nuevo ',
        telefono: ' ',
        notas: '\t',
      );
      await h.service.editarProveedor(update);
      final current = (await h.repository.watchProveedores().first).singleWhere(
        (s) => s.id == first.id,
      );
      expect(current.nombre, 'Nuevo');
      expect(current.telefono, isNull);
      expect(current.notas, isNull);
      expect(current.createdEventId, first.createdEventId);
      expect(current.version, 2);
    },
  );

  test(
    'stream emite vacío, alta y edición sin volver a suscribirse; trazabilidad y refs locales',
    () async {
      final stream = StreamIterator(h.repository.watchProveedores());
      addTearDown(stream.cancel);
      expect(await stream.moveNext(), isTrue);
      expect(stream.current, isEmpty);
      final nextCreate = stream.moveNext();
      await h.service.crearProveedor(
        const CrearProveedorCommand(nombre: 'Norte'),
      );
      await nextCreate;
      final base = stream.current.single;
      final nextEdit = stream.moveNext();
      await h.service.editarProveedor(edit(base, 'Sur'));
      await nextEdit;
      final after = stream.current.single;
      expect(after.nombre, 'Sur');
      expect(after.id, base.id);
      expect(after.version, 2);
      expect(after.createdEventId, base.createdEventId);
      final events = await h.events();
      expect(after.lastEventId, events.last.eventId);
      expect(events.last.baseVersion, 1);
      final payload = ProveedorActualizadoPayload.fromJson(events.last.payload);
      expect(payload.baseEventId, base.lastEventId);
      expect(payload.before.name, 'Norte');
      expect(payload.after.name, 'Sur');
      for (final append in h.appends) {
        expect(append.refs, hasLength(1));
        expect(
          append.refs.single.refType,
          ProveedorCreadoPayload.aggregateType,
        );
        expect(append.refs.single.refId, base.id);
        expect(append.refs.single.relationship, 'affects');
      }
      for (final event in events) {
        expect(event.deviceId, 'supplier-tablet');
        expect(event.userId, 'supplier-user');
        expect(event.createdAtLocal, isNotNull);
        expect(event.deliveryStatus, 'not_required');
      }
      expect(await h.db.select(h.db.eventRefs).get(), isEmpty);
      expect(await h.db.select(h.db.variantSuppliers).get(), isEmpty);
    },
  );

  test('conserva y comprueba una secuencia conocida al editar', () async {
    final initial = await create();
    final row = (await h.projection.findById(initial.id))!;
    await h.projection.save(
      ProveedorProjection(
        id: row.id,
        name: row.name,
        phone: row.phone,
        notes: row.notes,
        active: row.active,
        version: row.version,
        createdEventId: row.createdEventId,
        lastEventId: row.lastEventId,
        lastServerSequence: 42,
      ),
    );
    final base = (await h.repository.watchProveedores().first).single;
    await h.service.editarProveedor(edit(base, 'Con secuencia'));
    expect((await h.events()).last.baseServerSequence, 42);
    expect(
      (await h.repository.watchProveedores().first).single.lastServerSequence,
      42,
    );
  });

  test(
    'dos guardados concurrentes desde la misma base solo aplican uno',
    () async {
      final base = await create();
      final results = await Future.wait([
        for (final name in ['Primero', 'Segundo'])
          (() async {
            try {
              await h.service.editarProveedor(edit(base, name));
              return true;
            } on StateError {
              return false;
            }
          })(),
      ]);
      expect(results.where((result) => result), hasLength(1));
      expect(await h.events(), hasLength(2));
      expect((await h.repository.watchProveedores().first).single.version, 2);
      expect(await h.db.select(h.db.eventRefs).get(), isEmpty);
    },
  );

  test('edición sin cambios normalizados no registra evento', () async {
    final base = await create();
    await h.service.editarProveedor(
      EditarProveedorCommand(
        base: base,
        nombre: ' Norte ',
        telefono: ' ',
        notas: '',
      ),
    );
    expect(await h.events(), hasLength(1));
    expect((await h.repository.watchProveedores().first).single.version, 1);
  });

  test('base capturada antigua rechazada sin escritura parcial', () async {
    final base = await create();
    await h.service.editarProveedor(edit(base, 'Actual'));
    await expectLater(
      h.service.editarProveedor(edit(base, 'Perdedor')),
      throwsStateError,
    );
    expect(await h.events(), hasLength(2));
    expect(
      (await h.repository.watchProveedores().first).single.nombre,
      'Actual',
    );
    expect(await h.db.select(h.db.eventRefs).get(), isEmpty);
  });

  for (final field in ['evento', 'versión', 'secuencia', 'before']) {
    test('comando rechaza base con $field incompatible', () async {
      final base = await create();
      final wrong = Proveedor(
        id: base.id,
        nombre: field == 'before' ? 'Falso' : base.nombre,
        version: field == 'versión' ? 9 : base.version,
        createdEventId: base.createdEventId,
        lastEventId: field == 'evento'
            ? '00000000-0000-4000-8000-000000000010'
            : base.lastEventId,
        lastServerSequence: field == 'secuencia' ? 9 : base.lastServerSequence,
      );
      await expectLater(
        h.service.editarProveedor(edit(wrong, 'Cambio')),
        throwsStateError,
      );
      expect(await h.events(), hasLength(1));
      expect(
        (await h.repository.watchProveedores().first).single.nombre,
        'Norte',
      );
    });
    test(
      'handler revalida $field dentro de appendAndApply y revierte evento',
      () async {
        final base = await create();
        final event = SyncEvent(
          eventId: '00000000-0000-4000-8000-000000000020',
          aggregateId: base.id,
          aggregateType: ProveedorActualizadoPayload.aggregateType,
          eventType: ProveedorActualizadoPayload.eventType,
          deviceId: 'tablet',
          userId: 'user',
          baseVersion: field == 'versión' ? 9 : base.version,
          baseServerSequence: field == 'secuencia' ? 9 : null,
          createdAtLocal: DateTime(2026),
          payload: ProveedorActualizadoPayload(
            baseEventId: field == 'evento'
                ? '00000000-0000-4000-8000-000000000010'
                : base.lastEventId!,
            before: ProveedorCreadoPayload(
              name: field == 'before' ? 'Falso' : base.nombre,
            ),
            after: ProveedorCreadoPayload(name: 'Perdedor'),
          ).toJson(),
        );
        await expectLater(
          h.local.appendAndApply(
            event,
            refs: [
              LocalEventRef.affects(
                refType: ProveedorCreadoPayload.aggregateType,
                refId: base.id,
              ),
            ],
          ),
          throwsStateError,
        );
        expect(await h.events(), hasLength(1));
        expect(
          (await h.repository.watchProveedores().first).single.nombre,
          'Norte',
        );
      },
    );
  }

  test(
    'handlers idempotentes no duplican ni revierten ediciones; identidad ocupada falla',
    () async {
      final base = await create();
      final created = (await h.events()).single;
      await h.created.apply(created);
      await h.service.editarProveedor(edit(base, 'Editado'));
      final updated = (await h.events()).last;
      await h.updated.apply(updated);
      await h.created.apply(created);
      final current = (await h.repository.watchProveedores().first).single;
      expect(current.nombre, 'Editado');
      expect(current.version, 2);
      expect(current.createdEventId, created.eventId);
      expect(current.lastEventId, updated.eventId);
      await expectLater(
        h.created.apply(
          created.copyWith(eventId: '00000000-0000-4000-8000-000000000011'),
        ),
        throwsStateError,
      );
      expect(await h.repository.watchProveedores().first, hasLength(1));
    },
  );

  test(
    'fallo después de proyectar revierte toda la creación y toda la edición',
    () async {
      h.failAfterApply = true;
      await expectLater(create(), throwsStateError);
      expect(await h.events(), isEmpty);
      expect(await h.repository.watchProveedores().first, isEmpty);
      h.failAfterApply = false;
      final base = await create();
      h.failAfterApply = true;
      await expectLater(
        h.service.editarProveedor(edit(base, 'Fallido')),
        throwsStateError,
      );
      expect(await h.events(), hasLength(1));
      expect(
        (await h.repository.watchProveedores().first).single.nombre,
        'Norte',
      );
    },
  );

  test(
    'server_sync permite alta nueva y no importa una base standalone',
    () async {
      final base = await create();
      h.config.update(AppConfig.initial.copyWith(mode: AppMode.serverSync));
      await h.service.crearProveedor(const CrearProveedorCommand(nombre: 'Nuevo servidor'));
      await expectLater(
        h.service.editarProveedor(edit(base, 'Remoto')),
        throwsStateError,
      );
      expect(h.appends, hasLength(2));
      expect(await h.events(), hasLength(2));
      expect(await h.db.select(h.db.eventRefs).get(), hasLength(1));
    },
  );

  test(
    'persistencia compartida valida refs en ambos modos y solo las guarda en server_sync',
    () async {
      final base = await create();
      final event = (await h.events()).single.copyWith(
        eventId: '00000000-0000-4000-8000-000000000012',
        aggregateId: '00000000-0000-4000-8000-000000000013',
      );
      for (final mode in AppMode.values) {
        h.config.update(AppConfig.initial.copyWith(mode: mode));
        await expectLater(
          h.local.appendAndApply(event, refs: []),
          throwsArgumentError,
        );
      }
      expect(await h.events(), hasLength(1));
      // Solo prueba del adaptador; el servicio público permanece bloqueado.
      await h.local.appendAndApply(
        event,
        refs: [
          LocalEventRef.affects(
            refType: ProveedorCreadoPayload.aggregateType,
            refId: event.aggregateId,
          ),
        ],
      );
      expect(await h.db.select(h.db.eventRefs).get(), hasLength(1));
      expect((await h.events()).last.deliveryStatus, 'pending');
      expect(base.version, 1);
    },
  );

  test(
    'runtime standalone y catálogo no resuelven monitor de actividad remota',
    () async {
      var remoteCalls = 0;
      getIt.registerLazySingleton<SyncAvailabilityMonitor>(() {
        remoteCalls++;
        throw StateError(
          'No iniciar push, pull, preflight, health ni WebSocket.',
        );
      });
      addTearDown(() => getIt.unregister<SyncAvailabilityMonitor>());
      await startConfiguredRuntimeServices(
        AppConfig.initial.copyWith(
          setupCompleted: true,
          backupProvider: BackupProvider.none,
        ),
      );
      final base = await create();
      await h.service.editarProveedor(edit(base, 'Offline'));
      await stopConfiguredRuntimeServices(
        AppConfig.initial.copyWith(
          setupCompleted: true,
          backupProvider: BackupProvider.none,
        ),
      );
      expect(remoteCalls, 0);
      expect(await h.db.eventDao.obtenerEventosPendientes(), isEmpty);
      expect(await h.db.select(h.db.eventRefs).get(), isEmpty);
    },
  );

  test(
    'catálogo persiste después de cerrar y reabrir SQLite temporal',
    () async {
      final dir = await Directory.systemTemp.createTemp('supplier_phase2_');
      final file = File('${dir.path}/catalog.sqlite');
      await h.dispose();
      final first = ProveedorHarness(
        database: AppDatabase.forTesting(NativeDatabase(file)),
      );
      try {
        await first.service.crearProveedor(
          const CrearProveedorCommand(
            nombre: 'Persistente',
            telefono: '001',
            notas: 'Entrega',
          ),
        );
        final base = (await first.repository.watchProveedores().first).single;
        await first.service.editarProveedor(edit(base, 'Persistente editado'));
      } finally {
        await first.dispose();
      }
      final second = ProveedorHarness(
        database: AppDatabase.forTesting(NativeDatabase(file)),
      );
      try {
        final current =
            (await second.repository.watchProveedores().first).single;
        expect(current.nombre, 'Persistente editado');
        expect(current.version, 2);
        expect(await second.events(), hasLength(2));
        expect(await second.db.select(second.db.eventRefs).get(), isEmpty);
      } finally {
        await second.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
}
