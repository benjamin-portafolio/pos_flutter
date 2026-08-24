import '../models/sync_event.dart';
import '../payloads/categoria_actualizada_payload.dart';
import '../payloads/categoria_creada_payload.dart';
import '../payloads/categoria_eliminada_payload.dart';
import '../payloads/categoria_movida_payload.dart';
import '../projections/categoria_projection_store.dart';
import '../projections/producto_projection_store.dart';

class CategoriaEventHandler {
  CategoriaEventHandler(
    this._categoriaProjectionStore, [
    this._productoProjectionStore,
  ]);

  final CategoriaProjectionStore _categoriaProjectionStore;
  final ProductoProjectionStore? _productoProjectionStore;

  Future<void> applyCategoriaCreada(SyncEvent event) async {
    final payload = CategoriaCreadaPayload.fromJson(event.payload);
    final existing = await _categoriaProjectionStore.findById(
      event.aggregateId,
    );

    if (existing != null) {
      if (existing.createdEventId == event.eventId) {
        await _categoriaProjectionStore.update(
          CategoriaProjection(
            id: existing.id,
            nombre: payload.nombre,
            color: payload.color,
            orden: payload.orden,
            active: existing.active,
            version: existing.version,
            createdEventId: existing.createdEventId,
            lastEventId: event.eventId,
            lastServerSequence:
                event.serverSequence ?? existing.lastServerSequence,
          ),
        );
        return;
      }

      final removedLocalPending =
          await _removeLocalPendingProjectionForRemoteEvent(event, existing);
      if (!removedLocalPending) {
        throw StateError(
          'No se puede aplicar categoria_creada sobre una categoría existente: '
          '${event.aggregateId}',
        );
      }
    }

    await _categoriaProjectionStore.insert(
      CategoriaProjection(
        id: event.aggregateId,
        nombre: payload.nombre,
        color: payload.color,
        orden: payload.orden,
        active: true,
        version: event.baseVersion ?? 1,
        createdEventId: event.eventId,
        lastEventId: event.eventId,
        lastServerSequence: event.serverSequence,
      ),
    );
  }

  Future<void> applyCategoriaActualizada(SyncEvent event) async {
    final payload = CategoriaActualizadaPayload.fromJson(event.payload);
    final existing = await _categoriaProjectionStore.findById(
      event.aggregateId,
    );
    if (existing == null) {
      throw StateError(
        'No se puede aplicar categoria_actualizada porque no existe: '
        '${event.aggregateId}',
      );
    }

    if (existing.lastEventId == event.eventId) {
      await _categoriaProjectionStore.updateSyncMetadata(
        existing.id,
        eventId: event.eventId,
        serverSequence: event.serverSequence,
      );
      return;
    }

    final serverSequence = event.serverSequence;
    final currentServerSequence = existing.lastServerSequence;
    if (serverSequence != null &&
        currentServerSequence != null &&
        serverSequence <= currentServerSequence) {
      return;
    }

    if (serverSequence == null) {
      _validateLocalBase(event, payload, existing);
    }

    final remoteVersion = event.baseVersion == null
        ? existing.version + 1
        : event.baseVersion! + 1;
    await _categoriaProjectionStore.update(
      CategoriaProjection(
        id: existing.id,
        nombre: payload.nombreNuevo ?? existing.nombre,
        color: payload.colorNuevo ?? existing.color,
        orden: existing.orden,
        active: existing.active,
        version: serverSequence == null
            ? existing.version + 1
            : _max(existing.version, remoteVersion),
        createdEventId: existing.createdEventId,
        lastEventId: event.eventId,
        lastServerSequence: serverSequence ?? existing.lastServerSequence,
      ),
    );
  }

  Future<void> applyCategoriaMovida(SyncEvent event) async {
    final payload = CategoriaMovidaPayload.fromJson(event.payload);
    if (payload.categoriaDesplazadaId == event.aggregateId) {
      throw const FormatException(
        'categoria_movida requiere dos categorías diferentes.',
      );
    }

    final moved = await _categoriaProjectionStore.findById(event.aggregateId);
    final displaced = await _categoriaProjectionStore.findById(
      payload.categoriaDesplazadaId,
    );
    if (moved == null || displaced == null) {
      throw StateError(
        'No se puede aplicar categoria_movida porque falta una categoría.',
      );
    }

    if (moved.lastEventId == event.eventId &&
        displaced.lastEventId == event.eventId) {
      await _categoriaProjectionStore.updateSyncMetadata(
        moved.id,
        eventId: event.eventId,
        serverSequence: event.serverSequence,
      );
      await _categoriaProjectionStore.updateSyncMetadata(
        displaced.id,
        eventId: event.eventId,
        serverSequence: event.serverSequence,
      );
      return;
    }

    final serverSequence = event.serverSequence;
    if (serverSequence != null &&
        (_isOlderThanProjection(serverSequence, moved) ||
            _isOlderThanProjection(serverSequence, displaced))) {
      return;
    }

    if (serverSequence == null) {
      _validateLocalMoveBase(event, payload, moved, displaced);
    }

    final movedRemoteVersion = event.baseVersion == null
        ? moved.version + 1
        : event.baseVersion! + 1;
    final displacedRemoteVersion = payload.categoriaDesplazadaBaseVersion + 1;
    await _categoriaProjectionStore.update(
      CategoriaProjection(
        id: moved.id,
        nombre: moved.nombre,
        color: moved.color,
        orden: payload.ordenNuevo,
        active: moved.active,
        version: serverSequence == null
            ? moved.version + 1
            : _max(moved.version, movedRemoteVersion),
        createdEventId: moved.createdEventId,
        lastEventId: event.eventId,
        lastServerSequence: serverSequence ?? moved.lastServerSequence,
      ),
    );
    await _categoriaProjectionStore.update(
      CategoriaProjection(
        id: displaced.id,
        nombre: displaced.nombre,
        color: displaced.color,
        orden: payload.categoriaDesplazadaOrdenNuevo,
        active: displaced.active,
        version: serverSequence == null
            ? displaced.version + 1
            : _max(displaced.version, displacedRemoteVersion),
        createdEventId: displaced.createdEventId,
        lastEventId: event.eventId,
        lastServerSequence: serverSequence ?? displaced.lastServerSequence,
      ),
    );
  }

  Future<void> applyCategoriaEliminada(SyncEvent event) async {
    final payload = CategoriaEliminadaPayload.fromJson(event.payload);
    payload.validateForSourceCategory(event.aggregateId);
    if (event.aggregateType != CategoriaEliminadaPayload.aggregateType ||
        event.baseVersion == null ||
        event.baseVersion! < 1 ||
        event.baseServerSequence != null && event.baseServerSequence! < 0 ||
        payload.categoriasDesplazadas.any(
          (category) => category.categoriaId == event.aggregateId,
        )) {
      throw const FormatException(
        'Envelope inválido para categoria_eliminada.',
      );
    }
    final existing = await _categoriaProjectionStore.findById(
      event.aggregateId,
    );

    // El hard delete no conserva una proyección tombstone. La ausencia solo es
    // idempotente cuando las categorías desplazadas todavía acreditan que este
    // mismo evento ya aplicó la compactación.
    if (existing == null) {
      for (final linked in payload.productosVinculados) {
        final current = await _productoProjectionStore?.findProductById(
          linked.productoId,
        );
        if (current == null ||
            current.lastEventId != event.eventId ||
            current.categoriaId != linked.categoriaNuevaId) {
          throw StateError(
            'categoria_eliminada encontró productos que no acreditan su aplicación previa.',
          );
        }
      }
      for (final shifted in payload.categoriasDesplazadas) {
        final current = await _categoriaProjectionStore.findById(
          shifted.categoriaId,
        );
        if (current == null ||
            current.lastEventId != event.eventId ||
            current.orden != shifted.ordenNuevo) {
          throw StateError(
            'categoria_eliminada encontró una ausencia no atribuible al evento.',
          );
        }
      }
      return;
    }

    final ordered = await _categoriaProjectionStore.findAllOrdered();
    _validateConsecutiveOrder(ordered);
    _validateDeleteBase(event, payload, existing);
    final productStore = _productoProjectionStore;
    if (productStore == null && payload.productosVinculados.isNotEmpty) {
      throw StateError(
        'No está disponible la proyección de artículos para aplicar la eliminación.',
      );
    }
    final currentLinked = productStore == null
        ? const <ProductoProjection>[]
        : await productStore.findProductsByCategoryId(event.aggregateId);
    _validateLinkedProducts(event, payload, currentLinked);
    await _validateDestination(payload);

    final expectedShifted = ordered
        .where((category) => category.orden > existing.orden)
        .toList(growable: false);
    if (expectedShifted.length != payload.categoriasDesplazadas.length) {
      throw StateError(
        'categoria_eliminada no declara todas las categorías desplazadas.',
      );
    }
    for (var index = 0; index < expectedShifted.length; index++) {
      final current = expectedShifted[index];
      final declared = payload.categoriasDesplazadas[index];
      final currentBaseEventId = current.lastEventId ?? current.createdEventId;
      if (current.id != declared.categoriaId ||
          currentBaseEventId != declared.baseEventId ||
          current.version != declared.baseVersion ||
          declared.baseServerSequence != null &&
              current.lastServerSequence != declared.baseServerSequence ||
          current.orden != declared.ordenAnterior) {
        throw StateError(
          'categoria_eliminada no coincide con la base de orden local.',
        );
      }
    }

    for (final declared in payload.productosVinculados) {
      final current = currentLinked.firstWhere(
        (product) => product.id == declared.productoId,
      );
      await productStore!.updateProduct(
        ProductoProjection(
          id: current.id,
          nombre: current.nombre,
          categoriaId: declared.categoriaNuevaId,
          saleConfiguration: current.saleConfiguration,
          active: current.active,
          version: current.version + 1,
          createdEventId: current.createdEventId,
          lastEventId: event.eventId,
          lastServerSequence:
              event.serverSequence ?? current.lastServerSequence,
        ),
      );
    }

    await _categoriaProjectionStore.deleteById(existing.id);
    for (var index = 0; index < expectedShifted.length; index++) {
      final current = expectedShifted[index];
      final declared = payload.categoriasDesplazadas[index];
      await _categoriaProjectionStore.update(
        CategoriaProjection(
          id: current.id,
          nombre: current.nombre,
          color: current.color,
          orden: declared.ordenNuevo,
          active: current.active,
          version: current.version + 1,
          createdEventId: current.createdEventId,
          lastEventId: event.eventId,
          lastServerSequence:
              event.serverSequence ?? current.lastServerSequence,
        ),
      );
    }
  }

  void _validateLinkedProducts(
    SyncEvent event,
    CategoriaEliminadaPayload payload,
    List<ProductoProjection> current,
  ) {
    final currentById = {for (final product in current) product.id: product};
    if (currentById.length != payload.productosVinculados.length) {
      throw StateError(
        'categoria_eliminada no coincide con el conjunto actual de artículos.',
      );
    }
    for (final declared in payload.productosVinculados) {
      final product = currentById[declared.productoId];
      final baseEventId = product?.lastEventId ?? product?.createdEventId;
      if (product == null ||
          product.categoriaId != event.aggregateId ||
          declared.categoriaAnteriorId != event.aggregateId ||
          baseEventId != declared.baseEventId ||
          product.version != declared.baseVersion ||
          declared.baseServerSequence != null &&
              product.lastServerSequence != declared.baseServerSequence) {
        throw StateError(
          'categoria_eliminada no coincide con la base de un artículo.',
        );
      }
    }
  }

  Future<void> _validateDestination(CategoriaEliminadaPayload payload) async {
    final destination = payload.resolucionProductos.categoriaDestino;
    if (destination == null) return;
    final current = await _categoriaProjectionStore.findById(
      destination.categoriaId,
    );
    final baseEventId = current?.lastEventId ?? current?.createdEventId;
    if (current == null ||
        !current.active ||
        baseEventId != destination.baseEventId ||
        current.version != destination.baseVersion ||
        destination.baseServerSequence != null &&
            current.lastServerSequence != destination.baseServerSequence) {
      throw StateError(
        'categoria_eliminada no coincide con la base de la categoría destino.',
      );
    }
  }

  void _validateLocalBase(
    SyncEvent event,
    CategoriaActualizadaPayload payload,
    CategoriaProjection existing,
  ) {
    if (event.baseVersion != existing.version) {
      throw StateError(
        'categoria_actualizada partió de una versión local obsoleta.',
      );
    }
    if (payload.cambiaNombre && payload.nombreAnterior != existing.nombre) {
      throw StateError(
        'categoria_actualizada no coincide con el nombre local actual.',
      );
    }
    if (payload.cambiaColor && payload.colorAnterior != existing.color) {
      throw StateError(
        'categoria_actualizada no coincide con el color local actual.',
      );
    }
  }

  void _validateLocalMoveBase(
    SyncEvent event,
    CategoriaMovidaPayload payload,
    CategoriaProjection moved,
    CategoriaProjection displaced,
  ) {
    if (event.baseVersion != moved.version ||
        payload.categoriaDesplazadaBaseVersion != displaced.version) {
      throw StateError(
        'categoria_movida partió de una versión local obsoleta.',
      );
    }
    if (moved.orden != payload.ordenAnterior ||
        displaced.orden != payload.categoriaDesplazadaOrdenAnterior) {
      throw StateError(
        'categoria_movida no coincide con el orden local actual.',
      );
    }
  }

  void _validateDeleteBase(
    SyncEvent event,
    CategoriaEliminadaPayload payload,
    CategoriaProjection existing,
  ) {
    final snapshot = payload.categoriaEliminada;
    final currentBaseEventId = existing.lastEventId ?? existing.createdEventId;
    if (event.baseVersion != existing.version ||
        currentBaseEventId != payload.baseEventId ||
        existing.nombre != snapshot.nombre ||
        existing.color != snapshot.color ||
        existing.orden != snapshot.orden ||
        existing.active != snapshot.active ||
        existing.createdEventId != snapshot.createdEventId) {
      throw StateError(
        'categoria_eliminada no coincide con la instantánea local.',
      );
    }
  }

  void _validateConsecutiveOrder(List<CategoriaProjection> categories) {
    for (var index = 0; index < categories.length; index++) {
      if (categories[index].orden != index) {
        throw StateError(
          'categoria_eliminada requiere un orden local consecutivo.',
        );
      }
    }
  }

  bool _isOlderThanProjection(
    int serverSequence,
    CategoriaProjection projection,
  ) {
    final currentServerSequence = projection.lastServerSequence;
    return currentServerSequence != null &&
        serverSequence <= currentServerSequence;
  }

  int _max(int left, int right) => left > right ? left : right;

  Future<bool> _removeLocalPendingProjectionForRemoteEvent(
    SyncEvent event,
    CategoriaProjection existing,
  ) async {
    if (event.serverSequence == null || existing.lastServerSequence != null) {
      return false;
    }

    await _categoriaProjectionStore.deleteById(existing.id);
    return true;
  }
}
