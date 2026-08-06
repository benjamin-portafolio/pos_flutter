import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/producto_command_service.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/application/sync/projections/categoria_projection_store.dart';
import 'package:pos_flutter/domain/categorias/color_categoria.dart';

void main() {
  late _CapturingLocalEventStore eventStore;
  late _FakeCategoriaProjectionStore categoryStore;
  late ProductoCommandService service;

  setUp(() {
    eventStore = _CapturingLocalEventStore();
    categoryStore = _FakeCategoriaProjectionStore();
    service = ProductoCommandService(
      eventStore: eventStore,
      commandContext: const LocalCommandContext(
        deviceId: 'test_device',
        userId: 'test_user',
      ),
      categoriaProjectionStore: categoryStore,
    );
  });

  test('crea un producto sencillo canónico sin categoría', () async {
    await service.crearArticulo(
      const CrearArticuloCommand(
        nombre: '  Café americano  ',
        precioVenta: '45.50',
      ),
    );

    final event = eventStore.event!;
    final payload = ProductoCreadoPayload.fromJson(event.payload);
    expect(event.aggregateType, ProductoCreadoPayload.aggregateType);
    expect(event.eventType, ProductoCreadoPayload.eventType);
    expect(event.baseVersion, 1);
    expect(event.baseServerSequence, isNull);
    expect(payload.nombre, 'Café americano');
    expect(payload.categoriaId, isNull);
    expect(payload.variante.precioVentaMenor, 4550);
    expect(payload.variante.id, isNotEmpty);
    expect(eventStore.refs.map((ref) => ref.refType), [
      'product',
      'product_variant',
    ]);
  });

  test('captura la base y la referencia de la categoría elegida', () async {
    categoryStore.category = const CategoriaProjection(
      id: 'category_1',
      nombre: 'Bebidas',
      color: ColorCategoria.cyan,
      orden: 0,
      active: true,
      version: 2,
      createdEventId: 'category_event_1',
      lastEventId: 'category_event_2',
      lastServerSequence: 12,
    );

    await service.crearArticulo(
      const CrearArticuloCommand(
        nombre: 'Agua mineral',
        categoriaId: ' category_1 ',
        precioVenta: '30',
      ),
    );

    final payload = ProductoCreadoPayload.fromJson(eventStore.event!.payload);
    expect(payload.categoriaId, 'category_1');
    expect(payload.dependenciaCategoria?.baseEventId, 'category_event_2');
    expect(payload.dependenciaCategoria?.baseVersion, 2);
    expect(payload.dependenciaCategoria?.baseServerSequence, 12);
    expect(eventStore.refs.last.refType, 'category');
    expect(eventStore.refs.last.refId, 'category_1');
    expect(eventStore.refs.last.relationship, 'uses');
  });

  test('rechaza entradas inválidas antes de crear un evento', () async {
    await expectLater(
      service.crearArticulo(
        const CrearArticuloCommand(nombre: ' ', precioVenta: '0'),
      ),
      throwsA(isA<ArgumentError>()),
    );
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
  CategoriaProjection? category;

  @override
  Future<CategoriaProjection?> findById(String id) async =>
      category?.id == id ? category : null;

  @override
  Future<List<CategoriaProjection>> findAllOrdered() async => [
    ?category,
  ];

  @override
  Future<void> advanceLastServerSequence(String id, int serverSequence) async {}

  @override
  Future<void> deleteById(String id) async {}

  @override
  Future<void> deleteCreatedByEvent(String eventId) async {}

  @override
  Future<void> insert(CategoriaProjection projection) async {}

  @override
  Future<void> update(CategoriaProjection projection) async {}

  @override
  Future<void> updateSyncMetadata(
    String id, {
    required String eventId,
    int? serverSequence,
  }) async {}
}
