import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/categoria_command_service.dart';
import 'package:pos_flutter/application/commands/crear_categoria_command.dart';
import 'package:pos_flutter/application/commands/editar_categoria_command.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/projections/categoria_projection_store.dart';
import 'package:pos_flutter/domain/categorias/color_categoria.dart';

void main() {
  late _CapturingLocalEventStore eventStore;
  late _FakeCategoriaProjectionStore categoriaProjectionStore;
  late CategoriaCommandService service;

  setUp(() {
    eventStore = _CapturingLocalEventStore();
    categoriaProjectionStore = _FakeCategoriaProjectionStore();
    service = CategoriaCommandService(
      eventStore: eventStore,
      commandContext: const LocalCommandContext(
        deviceId: 'test_device',
        userId: 'test_user',
      ),
      categoriaProjectionStore: categoriaProjectionStore,
    );
  });

  test(
    'crearCategoria normaliza y crea el evento con una referencia',
    () async {
      await service.crearCategoria(
        const CrearCategoriaCommand(
          nombre: ' Bebidas ',
          color: ColorCategoria.cyan,
        ),
      );

      final event = eventStore.event!;
      expect(event.aggregateType, 'category');
      expect(event.eventType, 'categoria_creada');
      expect(event.baseVersion, 1);
      expect(event.payload, {
        'name': 'Bebidas',
        'color_key': 'cyan',
        'sort_order': null,
      });
      expect(eventStore.refs, hasLength(1));
      expect(eventStore.refs.single.refType, 'category');
      expect(eventStore.refs.single.refId, event.aggregateId);
      expect(eventStore.refs.single.relationship, 'affects');
    },
  );

  test('crearCategoria permite neutral cuando no se eligió color', () async {
    await service.crearCategoria(
      const CrearCategoriaCommand(
        nombre: 'Sin color',
        color: ColorCategoria.neutral,
      ),
    );

    expect(eventStore.event!.payload['color_key'], 'neutral');
  });

  test('crearCategoria rechaza nombres vacíos antes de guardar', () async {
    await expectLater(
      service.crearCategoria(
        const CrearCategoriaCommand(nombre: '  ', color: ColorCategoria.amber),
      ),
      throwsA(isA<ArgumentError>()),
    );

    expect(eventStore.event, isNull);
  });

  test(
    'editarCategoria crea un evento trazable con base y cambios reales',
    () async {
      categoriaProjectionStore.projection = const CategoriaProjection(
        id: 'category_1',
        nombre: 'Bebidas',
        color: ColorCategoria.cyan,
        orden: null,
        active: true,
        version: 3,
        createdEventId: 'event_created',
        lastEventId: 'event_previous',
        lastServerSequence: 18,
      );

      final changed = await service.editarCategoria(
        const EditarCategoriaCommand(
          categoriaId: 'category_1',
          nombre: ' Bebidas frías ',
          color: ColorCategoria.blue,
        ),
      );

      expect(changed, isTrue);
      final event = eventStore.event!;
      expect(event.aggregateType, 'category');
      expect(event.aggregateId, 'category_1');
      expect(event.eventType, 'categoria_actualizada');
      expect(event.baseVersion, 3);
      expect(event.baseServerSequence, 18);
      expect(event.payload, {
        'base_event_id': 'event_previous',
        'changed_fields': ['name', 'color_key'],
        'changes': {
          'name': {'from': 'Bebidas', 'to': 'Bebidas frías'},
          'color_key': {'from': 'cyan', 'to': 'blue'},
        },
      });
      expect(eventStore.refs.single.refType, 'category');
      expect(eventStore.refs.single.refId, 'category_1');
    },
  );

  test('editarCategoria no crea evento cuando no hay cambios', () async {
    categoriaProjectionStore.projection = const CategoriaProjection(
      id: 'category_1',
      nombre: 'Bebidas',
      color: ColorCategoria.cyan,
      orden: null,
      active: true,
      version: 1,
      createdEventId: 'event_created',
      lastEventId: 'event_created',
      lastServerSequence: null,
    );

    final changed = await service.editarCategoria(
      const EditarCategoriaCommand(
        categoriaId: 'category_1',
        nombre: ' Bebidas ',
        color: ColorCategoria.cyan,
      ),
    );

    expect(changed, isFalse);
    expect(eventStore.event, isNull);
  });
}

class _CapturingLocalEventStore implements LocalEventStore {
  SyncEvent? event;
  List<LocalEventRef> refs = const [];

  @override
  Future<void> appendAndApply(
    SyncEvent event, {
    required List<LocalEventRef> refs,
  }) async {
    this.event = event;
    this.refs = refs;
  }
}

class _FakeCategoriaProjectionStore implements CategoriaProjectionStore {
  CategoriaProjection? projection;

  @override
  Future<CategoriaProjection?> findById(String id) async => projection;

  @override
  Future<void> deleteById(String id) async {}

  @override
  Future<void> deleteCreatedByEvent(String eventId) async {}

  @override
  Future<void> insert(CategoriaProjection projection) async {
    this.projection = projection;
  }

  @override
  Future<void> update(CategoriaProjection projection) async {
    this.projection = projection;
  }

  @override
  Future<void> updateSyncMetadata(
    String id, {
    required String eventId,
    int? serverSequence,
  }) async {}
}
