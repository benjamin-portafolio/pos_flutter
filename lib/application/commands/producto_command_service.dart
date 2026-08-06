import 'package:uuid/uuid.dart';

import '../../domain/articulos/nombre_producto.dart';
import '../../domain/articulos/precio_venta.dart';
import '../sync/local_event_store.dart';
import '../sync/models/sync_event.dart';
import '../sync/payloads/producto_creado_payload.dart';
import '../sync/projections/categoria_projection_store.dart';
import 'crear_articulo_command.dart';
import 'local_command_context.dart';

class ProductoCommandService {
  ProductoCommandService({
    required LocalEventStore eventStore,
    required LocalCommandContext commandContext,
    required CategoriaProjectionStore categoriaProjectionStore,
  }) : _eventStore = eventStore,
       _commandContext = commandContext,
       _categoriaProjectionStore = categoriaProjectionStore;

  final LocalEventStore _eventStore;
  final LocalCommandContext _commandContext;
  final CategoriaProjectionStore _categoriaProjectionStore;
  final Uuid _uuid = const Uuid();

  Future<void> crearArticulo(CrearArticuloCommand command) async {
    final nombre = NombreProducto.fromInput(command.nombre);
    final precio = PrecioVenta.fromInput(command.precioVenta);
    final categoriaId = _normalizeOptional(command.categoriaId);
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
      ],
    );
  }

  Future<ProductoCreadoDependencia> _categoryDependency(
    String categoryId,
  ) async {
    final category = await _categoriaProjectionStore.findById(categoryId);
    if (category == null) {
      throw StateError('No existe la categoría seleccionada: $categoryId');
    }
    final baseEventId = category.lastEventId ?? category.createdEventId;
    if (baseEventId == null && category.lastServerSequence == null) {
      throw StateError(
        'La categoría seleccionada no tiene una base de sincronización.',
      );
    }
    return ProductoCreadoDependencia(
      refId: category.id,
      baseEventId: baseEventId,
      baseVersion: category.version,
      baseServerSequence: category.lastServerSequence,
    );
  }

  String? _normalizeOptional(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
