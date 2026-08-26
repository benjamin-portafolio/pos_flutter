import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/producto_command_service.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/application/sync/projections/categoria_projection_store.dart';
import 'package:pos_flutter/application/sync/synced_event_history.dart';
import 'package:pos_flutter/domain/categorias/color_categoria.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/unidad_inventario.dart';
import 'package:pos_flutter/domain/repositories/unidad_inventario_repository.dart';

void main() {
  late _CapturingLocalEventStore eventStore;
  late _FakeCategoriaProjectionStore categoryStore;
  late _FakeSyncedEventHistory eventHistory;
  late _FakeUnidadInventarioRepository unitRepository;
  late ProductoCommandService service;

  setUp(() {
    eventStore = _CapturingLocalEventStore();
    categoryStore = _FakeCategoriaProjectionStore();
    eventHistory = _FakeSyncedEventHistory();
    unitRepository = _FakeUnidadInventarioRepository();
    service = ProductoCommandService(
      eventStore: eventStore,
      commandContext: const LocalCommandContext(
        deviceId: 'test_device',
        userId: 'test_user',
      ),
      categoriaProjectionStore: categoryStore,
      syncedEventHistory: eventHistory,
      unidadInventarioRepository: unitRepository,
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
    expect(payload.variantes.single.precioVentaMenor, 4550);
    expect(payload.variantes.single.id, isNotEmpty);
    expect(eventStore.refs.map((ref) => ref.refType), [
      'product',
      'product_variant',
    ]);
  });

  test('crea un evento con varias variantes y todas sus refs', () async {
    await service.crearArticulo(
      const CrearArticuloCommand.conVariantes(
        nombre: 'Café',
        variantes: [
          CrearArticuloVarianteCommand(
            nombre: '  Ｇｒａｎｄｅ ',
            precioVenta: '10',
            costoEstandar: '2',
          ),
          CrearArticuloVarianteCommand(
            nombre: null,
            precioVenta: '12',
            costoEstandar: '0',
          ),
        ],
      ),
    );

    final event = eventStore.event!;
    final payload = ProductoCreadoPayload.fromJson(event.payload);
    expect(payload.variantes, hasLength(2));
    expect(payload.variantes.map((variant) => variant.nombre), [
      'Grande',
      null,
    ]);
    expect(payload.variantes.map((variant) => variant.costoEstandarMenor), [
      200,
      0,
    ]);
    expect(payload.variantes.map((variant) => variant.esPredeterminada), [
      true,
      false,
    ]);
    expect(payload.variantes.map((variant) => variant.orden), [0, 1]);
    expect(eventStore.refs.map((ref) => ref.refType), [
      'product',
      'product_variant',
      'product_variant_name',
      'product_variant',
    ]);
    expect(eventStore.refs[2].refId, '${event.aggregateId}:Z3JhbmRl');
    expect(eventStore.refs[2].relationship, 'requires_unique');
  });

  test('rechaza nombres duplicados antes de generar el evento', () async {
    await expectLater(
      service.crearArticulo(
        const CrearArticuloCommand.conVariantes(
          nombre: 'Café',
          variantes: [
            CrearArticuloVarianteCommand(
              nombre: 'Grande',
              precioVenta: '10',
              costoEstandar: null,
            ),
            CrearArticuloVarianteCommand(
              nombre: 'ＧＲＡＮＤＥ',
              precioVenta: '12',
              costoEstandar: null,
            ),
          ],
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(eventStore.event, isNull);
  });

  test(
    'depende de categoria_creada mientras su alta sigue pendiente',
    () async {
      categoryStore.category = const CategoriaProjection(
        id: 'category_1',
        nombre: 'Bebidas',
        color: ColorCategoria.cyan,
        orden: 0,
        active: true,
        version: 2,
        createdEventId: 'category_event_1',
        lastEventId: 'category_movement_2',
        lastServerSequence: null,
      );
      eventHistory.events['category_event_1'] = _categoryCreatedEvent();

      await service.crearArticulo(
        const CrearArticuloCommand(
          nombre: 'Agua mineral',
          categoriaId: ' category_1 ',
          precioVenta: '30',
        ),
      );

      final payload = ProductoCreadoPayload.fromJson(eventStore.event!.payload);
      expect(payload.categoriaId, 'category_1');
      expect(
        payload.dependenciaCategoria?.dependsOnEventId,
        'category_event_1',
      );
      expect(eventStore.refs.last.refType, 'category');
      expect(eventStore.refs.last.refId, 'category_1');
      expect(eventStore.refs.last.relationship, 'uses');
    },
  );

  test(
    'una categoría oficial no depende de su último evento de movimiento',
    () async {
      categoryStore.category = const CategoriaProjection(
        id: 'category_1',
        nombre: 'Bebidas',
        color: ColorCategoria.cyan,
        orden: 0,
        active: true,
        version: 3,
        createdEventId: 'category_created',
        lastEventId: 'movement_from_another_category',
        lastServerSequence: 20,
      );

      await service.crearArticulo(
        const CrearArticuloCommand(
          nombre: 'Agua mineral',
          categoriaId: 'category_1',
          precioVenta: '30',
        ),
      );

      final payload = ProductoCreadoPayload.fromJson(eventStore.event!.payload);
      expect(payload.categoriaId, 'category_1');
      expect(payload.dependenciaCategoria, isNull);
      expect(eventStore.refs.last.refId, 'category_1');
      expect(eventStore.refs.last.relationship, 'uses');
    },
  );

  test(
    'omite la dependencia si categoria_creada ya fue entregada antes del eco',
    () async {
      categoryStore.category = const CategoriaProjection(
        id: 'category_1',
        nombre: 'Bebidas',
        color: ColorCategoria.cyan,
        orden: 0,
        active: true,
        version: 1,
        createdEventId: 'category_event_1',
        lastEventId: 'category_event_1',
        lastServerSequence: null,
      );
      eventHistory.events['category_event_1'] = _categoryCreatedEvent(
        deliveryStatus: 'delivered',
      );

      await service.crearArticulo(
        const CrearArticuloCommand(
          nombre: 'Agua mineral',
          categoriaId: 'category_1',
          precioVenta: '30',
        ),
      );

      final payload = ProductoCreadoPayload.fromJson(eventStore.event!.payload);
      expect(payload.dependenciaCategoria, isNull);
    },
  );

  test('rechaza entradas inválidas antes de crear un evento', () async {
    await expectLater(
      service.crearArticulo(
        const CrearArticuloCommand(nombre: ' ', precioVenta: '0'),
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(eventStore.event, isNull);
  });

  test('measured usa atomicFactor y declara la referencia de unidad', () async {
    unitRepository.units['unit_kg'] = _kilogram;

    await service.crearArticulo(
      CrearArticuloCommand(
        nombre: 'Queso',
        precioVenta: '180',
        saleConfiguration: MeasuredSaleConfiguration(
          saleUnitId: 'unit_kg',
          priceReferenceQuantityAtomic: 1000,
        ),
      ),
    );

    final payload = ProductoCreadoPayload.fromJson(eventStore.event!.payload);
    expect(payload.saleConfiguration, isA<MeasuredSaleConfiguration>());
    expect(eventStore.refs.last.refType, 'unit');
    expect(eventStore.refs.last.refId, 'unit_kg');
    expect(eventStore.refs.last.relationship, 'uses');
  });

  test('rechaza una referencia distinta al atomicFactor', () async {
    unitRepository.units['unit_kg'] = _kilogram;

    await expectLater(
      service.crearArticulo(
        CrearArticuloCommand(
          nombre: 'Queso',
          precioVenta: '180',
          saleConfiguration: MeasuredSaleConfiguration(
            saleUnitId: 'unit_kg',
            priceReferenceQuantityAtomic: 1,
          ),
        ),
      ),
      throwsA(isA<StateError>()),
    );
    expect(eventStore.event, isNull);
  });
}

const _kilogram = UnidadInventario(
  id: 'unit_kg',
  code: 'kg',
  nombre: 'Kilogramo',
  simbolo: 'kg',
  dimension: DimensionUnidad.mass,
  factorAtomico: 1000,
  maximosDecimales: 3,
  activa: true,
);

SyncEvent _categoryCreatedEvent({String deliveryStatus = 'pending'}) {
  return SyncEvent(
    eventId: 'category_event_1',
    aggregateType: 'category',
    aggregateId: 'category_1',
    eventType: 'categoria_creada',
    deviceId: 'test_device',
    userId: 'test_user',
    createdAtLocal: DateTime.utc(2026, 8, 11),
    payload: const {'name': 'Bebidas', 'color_key': 'cyan', 'sort_order': 0},
    deliveryStatus: deliveryStatus,
  );
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
  Future<List<CategoriaProjection>> findAllOrdered() async => [?category];

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

class _FakeSyncedEventHistory implements SyncedEventHistory {
  final Map<String, SyncEvent> events = {};

  @override
  Future<SyncEvent?> eventById(String eventId) async => events[eventId];

  @override
  Future<List<SyncEvent>> eventsByTypeAfter({
    required String eventType,
    required int serverSequence,
  }) async => const [];

  @override
  Future<List<SyncEvent>> eventsForAggregateAfter({
    required String aggregateType,
    required String aggregateId,
    required int serverSequence,
  }) async => const [];
}

class _FakeUnidadInventarioRepository implements UnidadInventarioRepository {
  final Map<String, UnidadInventario> units = {};

  @override
  Future<List<UnidadInventario>> obtenerUnidadesActivas() async =>
      units.values.where((unit) => unit.activa).toList();

  @override
  Future<UnidadInventario?> obtenerUnidadPorId(String unidadId) async =>
      units[unidadId];
}
