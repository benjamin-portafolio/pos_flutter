import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/crear_recurso_inventario_command.dart';
import 'package:pos_flutter/application/commands/ajustar_existencia_inventario_command.dart';
import 'package:pos_flutter/application/commands/inventory_command_service.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/inventory_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/inventory_event_registry.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/recurso_inventario_creado_payload.dart';
import 'package:pos_flutter/application/sync/remote_event_applier.dart';
import 'package:pos_flutter/application/sync/server_echo_acknowledger.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_inventory_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_synced_event_store.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';

void main() {
  late AppDatabase db;
  late InventoryDao inventoryDao;
  late UnitDao unitDao;
  late DriftInventoryProjectionStore projectionStore;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    inventoryDao = InventoryDao(db);
    unitDao = UnitDao(db);
    projectionStore = DriftInventoryProjectionStore(
      inventoryDao: inventoryDao,
      unitDao: unitDao,
    );
  });

  tearDown(() => db.close());

  for (final mode in [AppMode.standalone, AppMode.serverSync]) {
    test(
      '${mode.name} guarda recurso, saldo, movimiento y refs correctas',
      () async {
        final service = InventoryCommandService(
          eventStore: _eventStore(db, projectionStore, mode),
          commandContext: const LocalCommandContext(
            deviceId: 'device-test',
            userId: 'user-test',
          ),
          inventoryProjectionStore: projectionStore,
        );

        await service.crearRecurso(
          const CrearRecursoInventarioCommand(
            nombre: ' Harina ',
            defaultUnitId: InventoryUnitIds.kilogram,
            quantityDeltaAtomic: -250,
            movementReason: ' Existencia inicial ',
          ),
        );

        final items = await db.select(db.inventoryItems).get();
        final balances = await db.select(db.inventoryBalances).get();
        final movements = await db.select(db.inventoryMovements).get();
        final events = await db.select(db.events).get();
        final refs = await db.select(db.eventRefs).get();

        expect(items.single.name, 'Harina');
        expect(items.single.defaultUnitId, InventoryUnitIds.kilogram);
        expect(balances.single.quantityOnHandAtomic, -250);
        expect(balances.single.quantityAvailableAtomic, -250);
        expect(movements.single.quantityDeltaAtomic, -250);
        expect(movements.single.reason, 'Existencia inicial');
        expect(
          events.single.deliveryStatus,
          mode == AppMode.standalone ? 'not_required' : 'pending',
        );
        expect(refs, mode == AppMode.standalone ? isEmpty : hasLength(3));
      },
    );
  }

  test('sin cantidad crea saldo cero y no crea movimiento', () async {
    final service = InventoryCommandService(
      eventStore: _eventStore(db, projectionStore, AppMode.standalone),
      commandContext: const LocalCommandContext(
        deviceId: 'device-test',
        userId: 'user-test',
      ),
      inventoryProjectionStore: projectionStore,
    );
    await service.crearRecurso(
      const CrearRecursoInventarioCommand(
        nombre: 'Vasos',
        defaultUnitId: InventoryUnitIds.piece,
      ),
    );

    expect(
      (await db.select(db.inventoryBalances).get()).single.quantityOnHandAtomic,
      0,
    );
    expect(await db.select(db.inventoryMovements).get(), isEmpty);
  });

  test('cada ajuste inserta movimiento y actualiza el balance atómicamente', () async {
    final service = InventoryCommandService(
      eventStore: _eventStore(db, projectionStore, AppMode.standalone),
      commandContext: const LocalCommandContext(
        deviceId: 'device-test',
        userId: 'user-test',
      ),
      inventoryProjectionStore: projectionStore,
    );
    await service.crearRecurso(
      const CrearRecursoInventarioCommand(
        nombre: 'Botellas',
        defaultUnitId: InventoryUnitIds.piece,
        quantityDeltaAtomic: 15,
        movementReason: 'Existencia inicial',
      ),
    );
    final itemId = (await db.select(db.inventoryItems).get()).single.id;

    await service.ajustarExistencia(
      AjustarExistenciaInventarioCommand(
        inventoryItemId: itemId,
        quantityDeltaAtomic: -3,
        reason: 'Merma por rotura',
      ),
    );

    expect(
      (await db.select(db.inventoryBalances).get())
          .single
          .quantityOnHandAtomic,
      12,
    );
    final movements = await db.select(db.inventoryMovements).get();
    expect(movements, hasLength(2));
    expect(movements.last.quantityDeltaAtomic, -3);
    expect(movements.last.reason, 'Merma por rotura');
    expect(await db.select(db.events).get(), hasLength(2));
  });

  test('reaplicar y recibir eco no duplica ni vuelve a sumar', () async {
    final handler = InventoryEventHandler(projectionStore);
    final processor = EventProcessor(handlers: inventoryEventHandlers(handler));
    final local = _event(serverSequence: null);
    await DriftLocalEventStore(
      db: db,
      eventDao: EventDao(db),
      eventRefDao: EventRefDao(db),
      eventProcessor: processor,
      appConfigController: AppConfigController(
        AppConfig.initial.copyWith(
          mode: AppMode.serverSync,
          setupCompleted: true,
        ),
      ),
    ).appendAndApply(
      local,
      refs: const [
        LocalEventRef.affects(
          refType: 'inventory_item',
          refId: '20000000-0000-4000-8000-000000000001',
        ),
      ],
    );
    await RemoteEventApplier(
      eventStore: DriftSyncedEventStore(db: db),
      eventProcessor: processor,
      serverEchoAcknowledger: ServerEchoAcknowledger(
        categoriaProjectionStore: DriftCategoriaProjectionStore(
          categoriaDao: CategoriaDao(db),
        ),
        inventoryProjectionStore: projectionStore,
      ),
    ).applySyncedEvents([_event(serverSequence: 42)]);

    expect(await db.select(db.inventoryItems).get(), hasLength(1));
    expect(await db.select(db.inventoryMovements).get(), hasLength(1));
    expect(
      (await db.select(db.inventoryBalances).get()).single.quantityOnHandAtomic,
      250,
    );
    expect(
      (await db.select(db.inventoryMovements).get()).single.serverSequence,
      42,
    );
    expect(
      (await db.select(db.events).get()).single.deliveryStatus,
      'delivered',
    );
  });

  test(
    'una creación oficial reemplaza una proyección local con UUID colisionado',
    () async {
      final handler = InventoryEventHandler(projectionStore);
      final localStore = DriftLocalEventStore(
        db: db,
        eventDao: EventDao(db),
        eventRefDao: EventRefDao(db),
        eventProcessor: EventProcessor(
          handlers: inventoryEventHandlers(handler),
        ),
        appConfigController: AppConfigController(
          AppConfig.initial.copyWith(
            mode: AppMode.serverSync,
            setupCompleted: true,
          ),
        ),
      );
      await localStore.appendAndApply(
        _event(),
        refs: const [
          LocalEventRef.affects(
            refType: 'inventory_item',
            refId: '20000000-0000-4000-8000-000000000001',
          ),
        ],
      );

      await handler.applyRecursoInventarioCreado(
        _event(
          eventId: '40000000-0000-4000-8000-000000000099',
          movementId: '30000000-0000-4000-8000-000000000099',
          serverSequence: 99,
        ),
      );

      final items = await db.select(db.inventoryItems).get();
      final balances = await db.select(db.inventoryBalances).get();
      final movements = await db.select(db.inventoryMovements).get();
      expect(items, hasLength(1));
      expect(
        items.single.createdEventId,
        '40000000-0000-4000-8000-000000000099',
      );
      expect(items.single.lastServerSequence, 99);
      expect(balances.single.quantityOnHandAtomic, 250);
      expect(movements, hasLength(1));
      expect(
        movements.single.movementId,
        '30000000-0000-4000-8000-000000000099',
      );
      expect(movements.single.serverSequence, 99);
    },
  );

  test(
    'un conflicto revierte evento y proyecciones de toda la transacción',
    () async {
      final store = _eventStore(db, projectionStore, AppMode.serverSync);
      await store.appendAndApply(
        _event(),
        refs: const [
          LocalEventRef.affects(
            refType: 'inventory_item',
            refId: '20000000-0000-4000-8000-000000000001',
          ),
        ],
      );

      expect(
        () => store.appendAndApply(
          _event(
            eventId: '40000000-0000-4000-8000-000000000002',
            movementId: '30000000-0000-4000-8000-000000000002',
          ),
          refs: const [
            LocalEventRef.affects(
              refType: 'inventory_item',
              refId: '20000000-0000-4000-8000-000000000001',
            ),
          ],
        ),
        throwsA(isA<Exception>()),
      );
      expect(await db.select(db.events).get(), hasLength(1));
      expect(await db.select(db.inventoryItems).get(), hasLength(1));
      expect(await db.select(db.inventoryMovements).get(), hasLength(1));
    },
  );
}

DriftLocalEventStore _eventStore(
  AppDatabase db,
  DriftInventoryProjectionStore projectionStore,
  AppMode mode,
) {
  return DriftLocalEventStore(
    db: db,
    eventDao: EventDao(db),
    eventRefDao: EventRefDao(db),
    eventProcessor: EventProcessor(
      handlers: inventoryEventHandlers(InventoryEventHandler(projectionStore)),
    ),
    appConfigController: AppConfigController(
      AppConfig.initial.copyWith(mode: mode, setupCompleted: true),
    ),
  );
}

SyncEvent _event({
  String eventId = '40000000-0000-4000-8000-000000000001',
  String movementId = '30000000-0000-4000-8000-000000000001',
  int? serverSequence,
}) {
  return SyncEvent(
    eventId: eventId,
    aggregateType: RecursoInventarioCreadoPayload.aggregateType,
    aggregateId: '20000000-0000-4000-8000-000000000001',
    eventType: RecursoInventarioCreadoPayload.eventType,
    deviceId: 'device-test',
    userId: 'user-test',
    baseVersion: 1,
    serverSequence: serverSequence,
    createdAtLocal: DateTime.utc(2026, 8, 19),
    payload: RecursoInventarioCreadoPayload.create(
      inventoryItemId: '20000000-0000-4000-8000-000000000001',
      name: 'Harina',
      defaultUnitId: InventoryUnitIds.kilogram,
      initialMovement: InitialInventoryMovementPayload.create(
        movementId: movementId,
        quantityDeltaAtomic: 250,
        reason: 'Existencia inicial',
      ),
    ).toJson(),
  );
}
