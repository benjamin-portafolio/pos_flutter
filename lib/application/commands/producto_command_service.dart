import 'package:uuid/uuid.dart';

import '../../domain/articulos/nombre_producto.dart';
import '../../domain/articulos/precio_venta.dart';
import '../../domain/articulos/sale_configuration.dart';
import '../../domain/inventario/dimension_unidad.dart';
import '../../domain/repositories/unidad_inventario_repository.dart';
import '../sync/local_event_store.dart';
import '../sync/models/sync_event.dart';
import '../sync/payloads/categoria_creada_payload.dart';
import '../sync/payloads/producto_creado_payload.dart';
import '../sync/projections/categoria_projection_store.dart';
import '../sync/synced_event_history.dart';
import 'crear_articulo_command.dart';
import 'local_command_context.dart';

class ProductoCommandService {
  ProductoCommandService({
    required LocalEventStore eventStore,
    required LocalCommandContext commandContext,
    required CategoriaProjectionStore categoriaProjectionStore,
    required SyncedEventHistory syncedEventHistory,
    required UnidadInventarioRepository unidadInventarioRepository,
  }) : _eventStore = eventStore,
       _commandContext = commandContext,
       _categoriaProjectionStore = categoriaProjectionStore,
       _syncedEventHistory = syncedEventHistory,
       _unidadInventarioRepository = unidadInventarioRepository;

  final LocalEventStore _eventStore;
  final LocalCommandContext _commandContext;
  final CategoriaProjectionStore _categoriaProjectionStore;
  final SyncedEventHistory _syncedEventHistory;
  final UnidadInventarioRepository _unidadInventarioRepository;
  final Uuid _uuid = const Uuid();

  Future<void> crearArticulo(CrearArticuloCommand command) async {
    final nombre = NombreProducto.fromInput(command.nombre);
    final precio = PrecioVenta.fromInput(command.precioVenta);
    final categoriaId = _normalizeOptional(command.categoriaId);
    final saleConfiguration = await _validateSaleConfiguration(
      command.saleConfiguration,
    );
    final dependency = categoriaId == null
        ? null
        : await _categoryDependency(categoriaId);
    final productId = _uuid.v4();
    final variantId = _uuid.v4();
    final payload = ProductoCreadoPayload.simple(
      nombre: nombre.value,
      categoriaId: categoriaId,
      varianteId: variantId,
      precioVentaMenor: precio.unidadMenor,
      saleConfiguration: saleConfiguration,
      dependenciaCategoria: dependency,
    );
    final event = SyncEvent(
      eventId: _uuid.v4(),
      aggregateType: ProductoCreadoPayload.aggregateType,
      aggregateId: productId,
      eventType: ProductoCreadoPayload.eventType,
      deviceId: _commandContext.deviceId,
      userId: _commandContext.userId,
      baseVersion: 1,
      createdAtLocal: DateTime.now(),
      payload: payload.toJson(),
    );

    await _eventStore.appendAndApply(
      event,
      refs: [
        LocalEventRef.affects(refType: 'product', refId: productId),
        LocalEventRef.affects(refType: 'product_variant', refId: variantId),
        if (categoriaId != null)
          LocalEventRef(
            refType: 'category',
            refId: categoriaId,
            relationship: 'uses',
          ),
        if (saleConfiguration is MeasuredSaleConfiguration)
          LocalEventRef.uses(
            refType: 'unit',
            refId: saleConfiguration.saleUnitId,
          ),
      ],
    );
  }

  Future<SaleConfiguration> _validateSaleConfiguration(
    SaleConfiguration configuration,
  ) async {
    if (configuration is UnitSaleConfiguration) return configuration;
    final measured = configuration as MeasuredSaleConfiguration;
    final unit = await _unidadInventarioRepository.obtenerUnidadPorId(
      measured.saleUnitId,
    );
    if (unit == null) {
      throw StateError('No existe la unidad de venta seleccionada.');
    }
    if (!unit.activa) {
      throw StateError('La unidad de venta seleccionada no está activa.');
    }
    if (unit.dimension != DimensionUnidad.mass &&
        unit.dimension != DimensionUnidad.volume) {
      throw StateError('La venta por fracción requiere masa o volumen.');
    }
    if (measured.priceReferenceQuantityAtomic != unit.factorAtomico) {
      throw StateError(
        'La referencia del precio debe coincidir con el factor de la unidad.',
      );
    }
    return measured;
  }

  Future<ProductoCreadoDependencia?> _categoryDependency(
    String categoryId,
  ) async {
    final category = await _categoriaProjectionStore.findById(categoryId);
    if (category == null) {
      throw StateError('No existe la categoría seleccionada: $categoryId');
    }
    if (category.lastServerSequence != null) return null;

    final createdEventId = category.createdEventId;
    if (createdEventId == null) {
      throw StateError(
        'La categoría seleccionada no tiene evento de creación.',
      );
    }
    final createdEvent = await _syncedEventHistory.eventById(createdEventId);
    if (createdEvent == null ||
        createdEvent.eventType != CategoriaCreadaPayload.eventType ||
        createdEvent.aggregateId != category.id) {
      throw StateError(
        'No se encontró el evento de creación de la categoría seleccionada.',
      );
    }

    return switch (createdEvent.deliveryStatus) {
      'pending' => ProductoCreadoDependencia(
        refId: category.id,
        dependsOnEventId: createdEvent.eventId,
      ),
      'delivered' || 'not_required' => null,
      'conflict' || 'rejected' => throw StateError(
        'La creación de la categoría seleccionada no fue aceptada.',
      ),
      final status => throw StateError(
        'Estado de creación de categoría no soportado: $status',
      ),
    };
  }

  String? _normalizeOptional(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
