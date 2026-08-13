import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/categoria_command_service.dart';
import 'package:pos_flutter/application/commands/crear_categoria_command.dart';
import 'package:pos_flutter/application/commands/editar_categoria_command.dart';
import 'package:pos_flutter/application/commands/eliminar_categoria_command.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/mover_categoria_command.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/projections/categoria_projection_store.dart';
import 'package:pos_flutter/application/sync/projections/producto_projection_store.dart';
import 'package:pos_flutter/domain/categorias/color_categoria.dart';
import 'package:pos_flutter/domain/categorias/direccion_movimiento_categoria.dart';

void main() {
  late _CapturingLocalEventStore eventStore;
  late _FakeCategoriaProjectionStore categoriaProjectionStore;
  late _FakeProductoProjectionStore productoProjectionStore;
  late CategoriaCommandService service;

  setUp(() {
    eventStore = _CapturingLocalEventStore();
    categoriaProjectionStore = _FakeCategoriaProjectionStore();
    productoProjectionStore = _FakeProductoProjectionStore();
    service = CategoriaCommandService(
      eventStore: eventStore,
      commandContext: const LocalCommandContext(
        deviceId: 'test_device',
        userId: 'test_user',
      ),
      categoriaProjectionStore: categoriaProjectionStore,
      productoProjectionStore: productoProjectionStore,
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
        'sort_order': 0,
      });
      expect(eventStore.refs, hasLength(1));
      expect(eventStore.refs.single.refType, 'category');
      expect(eventStore.refs.single.refId, event.aggregateId);
      expect(eventStore.refs.single.relationship, 'affects');
    },
  );

  test(
    'eliminarCategoria crea snapshot, desplazamientos y refs exactas',
    () async {
      categoriaProjectionStore.projections = const [
        CategoriaProjection(
          id: 'category_1',
          nombre: 'Bebidas',
          color: ColorCategoria.cyan,
          orden: 0,
          active: true,
          version: 2,
          createdEventId: 'created_1',
          lastEventId: 'base_1',
          lastServerSequence: 10,
        ),
        CategoriaProjection(
          id: 'category_2',
          nombre: 'Comida',
          color: ColorCategoria.amber,
          orden: 1,
          active: true,
          version: 3,
          createdEventId: 'created_2',
          lastEventId: 'base_2',
          lastServerSequence: 11,
        ),
      ];

      await service.eliminarCategoria(
        const EliminarCategoriaCommand(categoriaId: 'category_1'),
      );

      expect(eventStore.event!.eventType, 'categoria_eliminada');
      expect(eventStore.event!.baseVersion, 2);
      expect(eventStore.event!.baseServerSequence, 10);
      expect(eventStore.event!.payload['product_resolution'], {'type': 'none'});
      expect(eventStore.event!.payload['linked_products'], isEmpty);
      expect(eventStore.refs.map((ref) => ref.refId), [
        'category_1',
        'category_2',
      ]);
    },
  );

  test(
    'eliminarCategoria rechaza categoría inexistente y orden corrupto',
    () async {
      await expectLater(
        service.eliminarCategoria(
          const EliminarCategoriaCommand(categoriaId: 'missing'),
        ),
        throwsStateError,
      );
      categoriaProjectionStore.projections = const [
        CategoriaProjection(
          id: 'category_1',
          nombre: 'Bebidas',
          color: ColorCategoria.cyan,
          orden: 1,
          active: true,
          version: 1,
          createdEventId: 'created_1',
          lastEventId: 'created_1',
          lastServerSequence: null,
        ),
      ];
      await expectLater(
        service.eliminarCategoria(
          const EliminarCategoriaCommand(categoriaId: 'category_1'),
        ),
        throwsStateError,
      );

      categoriaProjectionStore.projections = const [
        CategoriaProjection(
          id: 'category_1',
          nombre: 'Bebidas',
          color: ColorCategoria.cyan,
          orden: 0,
          active: true,
          version: 1,
          createdEventId: null,
          lastEventId: null,
          lastServerSequence: null,
        ),
      ];
      await expectLater(
        service.eliminarCategoria(
          const EliminarCategoriaCommand(categoriaId: 'category_1'),
        ),
        throwsStateError,
      );
    },
  );

  for (final active in [true, false]) {
    test(
      'eliminarCategoria bloquea un producto ${active ? 'activo' : 'inactivo'}',
      () async {
        categoriaProjectionStore.projections = const [
          CategoriaProjection(
            id: 'category_1',
            nombre: 'Bebidas',
            color: ColorCategoria.cyan,
            orden: 0,
            active: true,
            version: 1,
            createdEventId: 'category_created',
            lastEventId: 'category_created',
            lastServerSequence: null,
          ),
        ];
        productoProjectionStore.linkedProductCount = 1;

        await expectLater(
          service.eliminarCategoria(
            const EliminarCategoriaCommand(categoriaId: 'category_1'),
          ),
          throwsStateError,
        );
        expect(eventStore.event, isNull);
      },
    );
  }

  test(
    'eliminarCategoria mueve productos y declara bases y refs exactas',
    () async {
      categoriaProjectionStore.projections = const [
        CategoriaProjection(
          id: 'category_1',
          nombre: 'Origen',
          color: ColorCategoria.cyan,
          orden: 0,
          active: true,
          version: 2,
          createdEventId: 'source_created',
          lastEventId: 'source_base',
          lastServerSequence: 10,
        ),
        CategoriaProjection(
          id: 'category_2',
          nombre: 'Destino',
          color: ColorCategoria.amber,
          orden: 1,
          active: true,
          version: 4,
          createdEventId: 'destination_created',
          lastEventId: 'destination_base',
          lastServerSequence: 30,
        ),
      ];
      productoProjectionStore.linkedProducts = const [
        ProductoProjection(
          id: 'product_2',
          nombre: 'Inactivo',
          categoriaId: 'category_1',
          active: false,
          version: 3,
          createdEventId: 'product_2_created',
          lastEventId: 'product_2_base',
          lastServerSequence: 26,
        ),
        ProductoProjection(
          id: 'product_1',
          nombre: 'Activo',
          categoriaId: 'category_1',
          active: true,
          version: 2,
          createdEventId: 'product_1_created',
          lastEventId: 'product_1_base',
          lastServerSequence: 25,
        ),
      ];

      await service.eliminarCategoria(
        const EliminarCategoriaCommand(
          categoriaId: 'category_1',
          resolucion: ResolucionProductosCategoria.move,
          categoriaDestinoId: 'category_2',
          productoIdsConfirmados: ['product_2', 'product_1'],
        ),
      );

      final payload = eventStore.event!.payload;
      expect(payload['product_resolution'], {
        'type': 'move',
        'destination_category': {
          'category_id': 'category_2',
          'base_event_id': 'destination_base',
          'base_version': 4,
          'base_server_sequence': 30,
        },
      });
      expect(
        (payload['linked_products']! as List).map(
          (value) => (value as Map)['product_id'],
        ),
        ['product_1', 'product_2'],
      );
      expect(
        eventStore.refs.map(
          (ref) => '${ref.refType}:${ref.refId}:${ref.relationship}',
        ),
        [
          'category:category_1:affects',
          'category:category_2:affects',
          'product:product_1:affects',
          'product:product_2:affects',
          'category:category_2:uses',
        ],
      );
    },
  );

  test('eliminarCategoria deja productos sin categoría', () async {
    categoriaProjectionStore.projections = const [
      CategoriaProjection(
        id: 'category_1',
        nombre: 'Origen',
        color: ColorCategoria.cyan,
        orden: 0,
        active: true,
        version: 1,
        createdEventId: 'source_created',
        lastEventId: 'source_base',
        lastServerSequence: null,
      ),
    ];
    productoProjectionStore.linkedProductCount = 1;

    await service.eliminarCategoria(
      const EliminarCategoriaCommand(
        categoriaId: 'category_1',
        resolucion: ResolucionProductosCategoria.uncategorize,
        productoIdsConfirmados: ['product_0'],
      ),
    );

    expect(eventStore.event!.payload['product_resolution'], {
      'type': 'uncategorize',
    });
    final linked =
        (eventStore.event!.payload['linked_products']! as List).single as Map;
    expect((linked['category_id'] as Map)['to'], isNull);
    expect(eventStore.refs.map((ref) => ref.refId), [
      'category_1',
      'product_0',
    ]);
  });

  test('eliminarCategoria rechaza si cambió el conjunto confirmado', () async {
    categoriaProjectionStore.projections = const [
      CategoriaProjection(
        id: 'category_1',
        nombre: 'Origen',
        color: ColorCategoria.cyan,
        orden: 0,
        active: true,
        version: 1,
        createdEventId: 'source_created',
        lastEventId: 'source_base',
        lastServerSequence: null,
      ),
    ];
    productoProjectionStore.linkedProductCount = 1;

    await expectLater(
      service.eliminarCategoria(
        const EliminarCategoriaCommand(
          categoriaId: 'category_1',
          resolucion: ResolucionProductosCategoria.uncategorize,
          productoIdsConfirmados: ['different_product'],
        ),
      ),
      throwsStateError,
    );
    expect(eventStore.event, isNull);
  });

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
        orden: 0,
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
      orden: 0,
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

  test('moverCategoria intercambia dos posiciones en un solo evento', () async {
    categoriaProjectionStore.projections = const [
      CategoriaProjection(
        id: 'category_1',
        nombre: 'Bebidas',
        color: ColorCategoria.cyan,
        orden: 0,
        active: true,
        version: 2,
        createdEventId: 'event_created_1',
        lastEventId: 'event_previous_1',
        lastServerSequence: 10,
      ),
      CategoriaProjection(
        id: 'category_2',
        nombre: 'Comidas',
        color: ColorCategoria.amber,
        orden: 1,
        active: true,
        version: 3,
        createdEventId: 'event_created_2',
        lastEventId: 'event_previous_2',
        lastServerSequence: 11,
      ),
    ];

    final moved = await service.moverCategoria(
      const MoverCategoriaCommand(
        categoriaId: 'category_2',
        direccion: DireccionMovimientoCategoria.arriba,
      ),
    );

    expect(moved, isTrue);
    final event = eventStore.event!;
    expect(event.eventType, 'categoria_movida');
    expect(event.aggregateId, 'category_2');
    expect(event.baseVersion, 3);
    expect(event.baseServerSequence, 11);
    expect(event.payload, {
      'base_event_id': 'event_previous_2',
      'changed_fields': ['sort_order'],
      'changes': {
        'sort_order': {'from': 1, 'to': 0},
      },
      'displaced_category': {
        'category_id': 'category_1',
        'base_event_id': 'event_previous_1',
        'base_version': 2,
        'base_server_sequence': 10,
        'sort_order': {'from': 0, 'to': 1},
      },
    });
    expect(eventStore.refs.map((ref) => ref.refId), [
      'category_2',
      'category_1',
    ]);
  });

  test('moverCategoria no crea evento fuera de los límites', () async {
    categoriaProjectionStore.projections = const [
      CategoriaProjection(
        id: 'category_1',
        nombre: 'Bebidas',
        color: ColorCategoria.cyan,
        orden: 0,
        active: true,
        version: 1,
        createdEventId: 'event_created',
        lastEventId: 'event_created',
        lastServerSequence: null,
      ),
    ];

    final moved = await service.moverCategoria(
      const MoverCategoriaCommand(
        categoriaId: 'category_1',
        direccion: DireccionMovimientoCategoria.arriba,
      ),
    );

    expect(moved, isFalse);
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
  List<CategoriaProjection> projections = [];

  CategoriaProjection? get projection =>
      projections.isEmpty ? null : projections.single;

  set projection(CategoriaProjection? value) {
    projections = value == null ? [] : [value];
  }

  @override
  Future<CategoriaProjection?> findById(String id) async {
    return projections.cast<CategoriaProjection?>().firstWhere(
      (projection) => projection?.id == id,
      orElse: () => null,
    );
  }

  @override
  Future<List<CategoriaProjection>> findAllOrdered() async =>
      List.of(projections)
        ..sort((left, right) => left.orden.compareTo(right.orden));

  @override
  Future<void> advanceLastServerSequence(String id, int serverSequence) async {}

  @override
  Future<void> deleteById(String id) async {}

  @override
  Future<void> deleteCreatedByEvent(String eventId) async {}

  @override
  Future<void> insert(CategoriaProjection projection) async {
    projections.add(projection);
  }

  @override
  Future<void> update(CategoriaProjection projection) async {
    final index = projections.indexWhere((value) => value.id == projection.id);
    if (index < 0) {
      projections.add(projection);
    } else {
      projections[index] = projection;
    }
  }

  @override
  Future<void> updateSyncMetadata(
    String id, {
    required String eventId,
    int? serverSequence,
  }) async {}
}

class _FakeProductoProjectionStore implements ProductoProjectionStore {
  List<ProductoProjection> linkedProducts = [];

  set linkedProductCount(int value) {
    linkedProducts = List.generate(
      value,
      (index) => ProductoProjection(
        id: 'product_$index',
        nombre: 'Producto $index',
        categoriaId: 'category_1',
        active: true,
        version: 1,
        createdEventId: 'product_event_$index',
        lastEventId: 'product_event_$index',
        lastServerSequence: null,
      ),
    );
  }

  @override
  Future<List<ProductoProjection>> findProductsByCategoryId(
    String categoryId,
  ) async {
    return linkedProducts
        .where((product) => product.categoriaId == categoryId)
        .toList(growable: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
