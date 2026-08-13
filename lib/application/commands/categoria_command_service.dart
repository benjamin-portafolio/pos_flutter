import 'package:uuid/uuid.dart';

import '../../domain/categorias/direccion_movimiento_categoria.dart';
import '../../domain/categorias/nombre_categoria.dart';
import '../sync/local_event_store.dart';
import '../sync/models/sync_event.dart';
import '../sync/payloads/categoria_actualizada_payload.dart';
import '../sync/payloads/categoria_creada_payload.dart';
import '../sync/payloads/categoria_eliminada_payload.dart';
import '../sync/payloads/categoria_movida_payload.dart';
import '../sync/projections/categoria_projection_store.dart';
import '../sync/projections/producto_projection_store.dart';
import 'crear_categoria_command.dart';
import 'editar_categoria_command.dart';
import 'eliminar_categoria_command.dart';
import 'local_command_context.dart';
import 'mover_categoria_command.dart';

class CategoriaCommandService {
  CategoriaCommandService({
    required LocalEventStore eventStore,
    required LocalCommandContext commandContext,
    required CategoriaProjectionStore categoriaProjectionStore,
    ProductoProjectionStore? productoProjectionStore,
  }) : _eventStore = eventStore,
       _commandContext = commandContext,
       _categoriaProjectionStore = categoriaProjectionStore,
       _productoProjectionStore = productoProjectionStore;

  final LocalEventStore _eventStore;
  final LocalCommandContext _commandContext;
  final CategoriaProjectionStore _categoriaProjectionStore;
  final ProductoProjectionStore? _productoProjectionStore;
  final Uuid _uuid = const Uuid();

  Future<void> crearCategoria(CrearCategoriaCommand command) async {
    final nombre = NombreCategoria.fromInput(command.nombre);
    final categorias = await _categoriaProjectionStore.findAllOrdered();
    final categoryId = _uuid.v4();
    final payload = CategoriaCreadaPayload(
      nombre: nombre.value,
      color: command.color,
      orden: categorias.length,
    );
    final event = SyncEvent(
      eventId: _uuid.v4(),
      aggregateType: CategoriaCreadaPayload.aggregateType,
      aggregateId: categoryId,
      eventType: CategoriaCreadaPayload.eventType,
      deviceId: _commandContext.deviceId,
      userId: _commandContext.userId,
      baseVersion: 1,
      createdAtLocal: DateTime.now(),
      payload: payload.toJson(),
    );

    await _eventStore.appendAndApply(
      event,
      refs: [LocalEventRef.affects(refType: 'category', refId: categoryId)],
    );
  }

  Future<bool> editarCategoria(EditarCategoriaCommand command) async {
    final nombre = NombreCategoria.fromInput(command.nombre);
    final existing = await _categoriaProjectionStore.findById(
      command.categoriaId,
    );
    if (existing == null) {
      throw StateError(
        'No existe la categoría que se intenta editar: ${command.categoriaId}',
      );
    }

    final baseEventId = existing.lastEventId ?? existing.createdEventId;
    if (baseEventId == null) {
      throw StateError(
        'La categoría no tiene un evento base para registrar la edición.',
      );
    }
    final payload = CategoriaActualizadaPayload.fromValues(
      baseEventId: baseEventId,
      nombreAnterior: existing.nombre,
      nombreNuevo: nombre.value,
      colorAnterior: existing.color,
      colorNuevo: command.color,
    );
    if (!payload.tieneCambios) return false;

    final event = SyncEvent(
      eventId: _uuid.v4(),
      aggregateType: CategoriaActualizadaPayload.aggregateType,
      aggregateId: existing.id,
      eventType: CategoriaActualizadaPayload.eventType,
      deviceId: _commandContext.deviceId,
      userId: _commandContext.userId,
      baseServerSequence: existing.lastServerSequence,
      baseVersion: existing.version,
      createdAtLocal: DateTime.now(),
      payload: payload.toJson(),
    );

    await _eventStore.appendAndApply(
      event,
      refs: [LocalEventRef.affects(refType: 'category', refId: existing.id)],
    );
    return true;
  }

  Future<bool> moverCategoria(MoverCategoriaCommand command) async {
    final categorias = await _categoriaProjectionStore.findAllOrdered();
    _validateConsecutiveOrder(categorias);

    final currentIndex = categorias.indexWhere(
      (categoria) => categoria.id == command.categoriaId,
    );
    if (currentIndex < 0) {
      throw StateError(
        'No existe la categoría que se intenta mover: ${command.categoriaId}',
      );
    }

    final displacedIndex = switch (command.direccion) {
      DireccionMovimientoCategoria.arriba => currentIndex - 1,
      DireccionMovimientoCategoria.abajo => currentIndex + 1,
    };
    if (displacedIndex < 0 || displacedIndex >= categorias.length) {
      return false;
    }

    final moved = categorias[currentIndex];
    final displaced = categorias[displacedIndex];
    final movedBaseEventId = _baseEventId(moved);
    final displacedBaseEventId = _baseEventId(displaced);
    final payload = CategoriaMovidaPayload.fromValues(
      baseEventId: movedBaseEventId,
      ordenAnterior: moved.orden,
      ordenNuevo: displaced.orden,
      categoriaDesplazadaId: displaced.id,
      categoriaDesplazadaBaseEventId: displacedBaseEventId,
      categoriaDesplazadaBaseVersion: displaced.version,
      categoriaDesplazadaBaseServerSequence: displaced.lastServerSequence,
      categoriaDesplazadaOrdenAnterior: displaced.orden,
      categoriaDesplazadaOrdenNuevo: moved.orden,
    );
    final event = SyncEvent(
      eventId: _uuid.v4(),
      aggregateType: CategoriaMovidaPayload.aggregateType,
      aggregateId: moved.id,
      eventType: CategoriaMovidaPayload.eventType,
      deviceId: _commandContext.deviceId,
      userId: _commandContext.userId,
      baseServerSequence: moved.lastServerSequence,
      baseVersion: moved.version,
      createdAtLocal: DateTime.now(),
      payload: payload.toJson(),
    );

    await _eventStore.appendAndApply(
      event,
      refs: [
        LocalEventRef.affects(refType: 'category', refId: moved.id),
        LocalEventRef.affects(refType: 'category', refId: displaced.id),
      ],
    );
    return true;
  }

  Future<void> eliminarCategoria(EliminarCategoriaCommand command) async {
    final productoProjectionStore = _productoProjectionStore;
    if (productoProjectionStore == null) {
      throw StateError(
        'No está disponible la proyección de artículos para eliminar.',
      );
    }

    // Estas son las lecturas base definitivas. El handler vuelve a validarlas
    // dentro de la transacción de appendAndApply antes de modificar proyecciones.
    final currentCategories = await _categoriaProjectionStore.findAllOrdered();
    _validateConsecutiveOrder(currentCategories, action: 'eliminar');
    final currentIndex = currentCategories.indexWhere(
      (categoria) => categoria.id == command.categoriaId,
    );
    if (currentIndex < 0) {
      throw StateError(
        'No existe la categoría que se intenta eliminar: '
        '${command.categoriaId}',
      );
    }
    final deleted = currentCategories[currentIndex];
    final linkedProducts = await productoProjectionStore
        .findProductsByCategoryId(deleted.id);
    final actualProductIds =
        linkedProducts.map((product) => product.id).toList(growable: false)
          ..sort();
    final confirmedProductIds = command.productoIdsConfirmados.toList()..sort();
    if (confirmedProductIds.toSet().length != confirmedProductIds.length ||
        !_sameStrings(actualProductIds, confirmedProductIds)) {
      throw StateError(
        'El conjunto de artículos vinculados cambió desde la confirmación.',
      );
    }

    final baseEventId = _baseEventId(deleted);
    final createdEventId = deleted.createdEventId;
    if (createdEventId == null) {
      throw StateError(
        'La categoría no tiene un evento creador para restaurar la proyección.',
      );
    }

    final shifted = currentCategories
        .skip(currentIndex + 1)
        .map((category) {
          return CategoriaEliminadaCategoriaDesplazada(
            categoriaId: category.id,
            baseEventId: _baseEventId(category),
            baseVersion: category.version,
            baseServerSequence: category.lastServerSequence,
            ordenAnterior: category.orden,
            ordenNuevo: category.orden - 1,
          );
        })
        .toList(growable: false);

    CategoriaEliminadaResolucion productResolution;
    String? targetCategoryId;
    switch (command.resolucion) {
      case ResolucionProductosCategoria.none:
        if (linkedProducts.isNotEmpty || command.categoriaDestinoId != null) {
          throw StateError(
            'La resolución none solo puede eliminar una categoría vacía.',
          );
        }
        productResolution = const CategoriaEliminadaResolucion.none();
      case ResolucionProductosCategoria.move:
        final destinationId = command.categoriaDestinoId;
        if (destinationId == null || destinationId.trim().isEmpty) {
          throw StateError('Mover artículos requiere una categoría destino.');
        }
        if (destinationId == deleted.id) {
          throw StateError(
            'La categoría destino debe ser diferente de la categoría origen.',
          );
        }
        final destinationIndex = currentCategories.indexWhere(
          (category) => category.id == destinationId,
        );
        final destination = destinationIndex < 0
            ? null
            : currentCategories[destinationIndex];
        if (destination == null || !destination.active) {
          throw StateError('La categoría destino no está disponible.');
        }
        targetCategoryId = destination.id;
        productResolution = CategoriaEliminadaResolucion.move(
          CategoriaEliminadaCategoriaDestino(
            categoriaId: destination.id,
            baseEventId: _baseEventId(destination),
            baseVersion: destination.version,
            baseServerSequence: destination.lastServerSequence,
          ),
        );
      case ResolucionProductosCategoria.uncategorize:
        if (command.categoriaDestinoId != null) {
          throw StateError(
            'Dejar sin categoría no admite una categoría destino.',
          );
        }
        productResolution = const CategoriaEliminadaResolucion.uncategorize();
    }

    final linkedPayload =
        linkedProducts
            .map(
              (product) => CategoriaEliminadaProductoVinculado(
                productoId: product.id,
                baseEventId: _productBaseEventId(product),
                baseVersion: product.version,
                baseServerSequence: product.lastServerSequence,
                categoriaAnteriorId: deleted.id,
                categoriaNuevaId: targetCategoryId,
              ),
            )
            .toList(growable: false)
          ..sort((left, right) => left.productoId.compareTo(right.productoId));
    final payload = CategoriaEliminadaPayload.fromValues(
      baseEventId: baseEventId,
      categoriaEliminada: CategoriaEliminadaSnapshot(
        nombre: deleted.nombre,
        color: deleted.color,
        orden: deleted.orden,
        active: deleted.active,
        createdEventId: createdEventId,
      ),
      resolucionProductos: productResolution,
      productosVinculados: linkedPayload,
      categoriasDesplazadas: shifted,
    );
    payload.validateForSourceCategory(deleted.id);
    final event = SyncEvent(
      eventId: _uuid.v4(),
      aggregateType: CategoriaEliminadaPayload.aggregateType,
      aggregateId: deleted.id,
      eventType: CategoriaEliminadaPayload.eventType,
      deviceId: _commandContext.deviceId,
      userId: _commandContext.userId,
      baseServerSequence: deleted.lastServerSequence,
      baseVersion: deleted.version,
      createdAtLocal: DateTime.now(),
      payload: payload.toJson(),
    );

    await _eventStore.appendAndApply(
      event,
      refs: [
        LocalEventRef.affects(refType: 'category', refId: deleted.id),
        ...shifted.map(
          (category) => LocalEventRef.affects(
            refType: 'category',
            refId: category.categoriaId,
          ),
        ),
        ...linkedPayload.map(
          (product) => LocalEventRef.affects(
            refType: 'product',
            refId: product.productoId,
          ),
        ),
        if (targetCategoryId != null)
          LocalEventRef.uses(refType: 'category', refId: targetCategoryId),
      ],
    );
  }

  String _productBaseEventId(ProductoProjection projection) {
    final value = projection.lastEventId ?? projection.createdEventId;
    if (value == null) {
      throw StateError('El artículo ${projection.id} no tiene un evento base.');
    }
    return value;
  }

  bool _sameStrings(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  String _baseEventId(CategoriaProjection projection) {
    final value = projection.lastEventId ?? projection.createdEventId;
    if (value == null) {
      throw StateError(
        'La categoría ${projection.id} no tiene un evento base.',
      );
    }
    return value;
  }

  void _validateConsecutiveOrder(
    List<CategoriaProjection> categorias, {
    String action = 'mover',
  }) {
    for (var index = 0; index < categorias.length; index++) {
      if (categorias[index].orden != index) {
        throw StateError(
          'El orden de categorías debe ser consecutivo antes de $action.',
        );
      }
    }
  }
}
