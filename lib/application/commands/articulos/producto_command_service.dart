import '../../../domain/articulos/proveedor_variante.dart';
import '../../sync/payloads/producto_proveedor_precio.dart';
import '../../sync/payloads/producto_proveedor_dependencia.dart';
import '../../sync/payloads/proveedor_creado_payload.dart';
import '../../sync/projections/proveedor_projection_store.dart';
import 'producto_inventory_update_result.dart';
import '../../sync/inventory_discard_policy.dart';
import '../../sync/payloads/recurso_inventario_descartado_payload.dart';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../domain/articulos/codigo_barras.dart';
import '../../../domain/articulos/costo_estandar.dart';
import '../../../domain/articulos/nombre_producto.dart';
import '../../../domain/articulos/nombre_variante.dart';
import '../../../domain/articulos/precio_venta.dart';
import '../../../domain/articulos/sale_configuration.dart';
import '../../../domain/inventario/dimension_unidad.dart';
import '../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../domain/inventario/tipo_movimiento_inventario.dart';
import '../../../domain/inventario/unidad_inventario.dart';
import '../../../domain/repositories/unidad_inventario_repository.dart';
import '../../sync/local_event_store.dart';
import '../../sync/models/sync_event.dart';
import '../../sync/payloads/categoria_creada_payload.dart';
import '../../sync/payloads/producto_creado_payload.dart';
import '../../sync/payloads/recurso_inventario_creado_payload.dart';
import '../../sync/projections/categoria_projection_store.dart';
import '../../sync/projections/inventory_projection_store.dart';
import '../../sync/synced_event_history.dart';
import 'crear_articulo_command.dart';
import 'crear_articulo_variante_command.dart';
import '../../sync/payloads/producto_actualizado_payload.dart';
import '../../sync/projections/producto_projection_store.dart';
import '../../sync/projections/variant_inventory_memory_store.dart';
import '../../sync/projections/variant_inventory_tracking_store.dart';
import '../local_command_context.dart';
import 'inventory_resource_resolver.dart';
import 'recurso_recuperacion_resultado.dart';

class ProductoCommandService {
  ProductoCommandService({
    required LocalEventStore eventStore,
    required LocalCommandContext commandContext,
    required CategoriaProjectionStore categoriaProjectionStore,
    required SyncedEventHistory syncedEventHistory,
    required UnidadInventarioRepository unidadInventarioRepository,
    InventoryProjectionStore? inventoryProjectionStore,
    ProductoProjectionStore? productoProjectionStore,
    ProveedorProjectionStore? proveedorProjectionStore,
    VariantInventoryMemoryStore? variantInventoryMemoryStore,
    VariantInventoryTrackingStore? variantInventoryTrackingStore,
  }) : _proveedorProjectionStore = proveedorProjectionStore,
       _productoProjectionStore = productoProjectionStore,
       _eventStore = eventStore,
       _commandContext = commandContext,
       _categoriaProjectionStore = categoriaProjectionStore,
       _syncedEventHistory = syncedEventHistory,
       _unidadInventarioRepository = unidadInventarioRepository,
       _inventoryProjectionStore = inventoryProjectionStore,
       _variantInventoryMemoryStore = variantInventoryMemoryStore,
       _variantInventoryTrackingStore = variantInventoryTrackingStore;

  final ProveedorProjectionStore? _proveedorProjectionStore;
  final ProductoProjectionStore? _productoProjectionStore;

  bool get _isStandalone =>
      _eventStore is LocalTransactionalEventStore &&
      (_eventStore as LocalTransactionalEventStore).isStandalone;

  Future<ProductoCreadoPayload> _snapshotForEdit(String productId) async {
    final current = await _productoProjectionStore!.snapshot(productId);
    return _proveedorProjectionStore != null
        ? current.withKnownSuppliers()
        : current;
  }

  final LocalEventStore _eventStore;
  final LocalCommandContext _commandContext;
  final CategoriaProjectionStore _categoriaProjectionStore;
  final SyncedEventHistory _syncedEventHistory;
  final UnidadInventarioRepository _unidadInventarioRepository;
  final InventoryProjectionStore? _inventoryProjectionStore;
  final VariantInventoryMemoryStore? _variantInventoryMemoryStore;
  final VariantInventoryTrackingStore? _variantInventoryTrackingStore;

  final Uuid _uuid = const Uuid();
  static const _quantityCodec = InventoryQuantityCodec();

  Future<ProductoProjection> _obtenerBaseEdicion(String id) async {
    final product = await _productoProjectionStore?.findProductById(id);
    if (product == null || !product.active) {
      throw StateError('El artículo no existe.');
    }
    if (!_isStandalone &&
        product.lastEventId != null &&
        (await _syncedEventHistory.eventById(
              product.lastEventId!,
            ))?.deliveryStatus ==
            'not_required') {
      throw StateError(
        'El historial local requiere una importación explícita.',
      );
    }
    return product;
  }

  Future<ProductoInventoryUpdateResult> actualizarArticulo({
    required String productId,
    required String baseEventId,
    required CrearArticuloCommand command,
    required List<String?> variantIds,
  }) => _runInTransaction(
    () => _actualizarArticulo(
      productId: productId,
      baseEventId: baseEventId,
      command: command,
      variantIds: variantIds,
    ),
  );

  Future<T> _runInTransaction<T>(Future<T> Function() action) {
    final store = _eventStore;
    return store is LocalTransactionalEventStore
        ? (store as LocalTransactionalEventStore).runInTransaction(action)
        : action();
  }

  Future<ProductoInventoryUpdateResult> _actualizarArticulo({
    required String productId,
    required String baseEventId,
    required CrearArticuloCommand command,
    required List<String?> variantIds,
  }) async {
    final product = await _obtenerBaseEdicion(productId);
    if (product.lastEventId != baseEventId) {
      throw StateError('El artículo cambió. Vuelve a abrirlo.');
    }
    final before = await _snapshotForEdit(productId);
    if (product.saleConfiguration != command.saleConfiguration) {
      throw const FormatException('No se puede cambiar la forma de venta.');
    }
    final article = await _prepareArticulo(
      command,
      existingProductId: productId,
      before: before,
      existingVariantIds: variantIds,
    );
    final payload = ProductoActualizadoPayload(
      baseEventId: product.lastEventId!,
      before: before,
      after: article.payload,
    );
    final event = SyncEvent(
      eventId: article.eventId,
      aggregateType: ProductoActualizadoPayload.aggregateType,
      aggregateId: article.productId,
      eventType: ProductoActualizadoPayload.eventType,
      deviceId: _commandContext.deviceId,
      userId: _commandContext.userId,
      baseVersion: product.version,
      baseServerSequence:
          (await _syncedEventHistory.eventById(
                product.lastEventId!,
              ))?.deliveryStatus ==
              'pending'
          ? null
          : product.lastServerSequence,
      createdAtLocal: DateTime.now(),
      payload: payload.toJson(),
    );
    await _appendArticulo(article, event, updatePayload: payload);
    final store = _eventStore;
    if (store is! LocalTransactionalEventStore ||
        !(store as LocalTransactionalEventStore).isStandalone) {
      return ProductoInventoryUpdateResult();
    }
    final discarded = <String>[];
    final reasons = <String, String>{};
    final tracking = _variantInventoryTrackingStore;
    final memory = _variantInventoryMemoryStore;
    final inventory = _inventoryProjectionStore;
    final candidates = before.variantes
        .where(
          (v) =>
              v.inventoryItemId != null &&
              payload.after.variantes.any(
                (a) => a.id == v.id && a.inventoryItemId == null,
              ),
        )
        .toList();
    if (candidates.isNotEmpty &&
        (tracking == null || memory == null || inventory == null)) {
      throw StateError('No se configuró el seguimiento seguro de inventario.');
    }
    for (final variant in candidates) {
      final item = await inventory!.findItemById(variant.inventoryItemId!);
      if (item == null) {
        throw StateError('Falta el recurso que acaba de desvincularse.');
      }
      final reason = await InventoryDiscardPolicy(
        trackingStore: tracking!,
        memoryStore: memory!,
      ).preservationReason(item, variant.id);
      if (reason != null) {
        reasons[item.id] = reason;
        continue;
      }
      final discardPayload = RecursoInventarioDescartadoPayload.create(
        baseEventId: item.lastEventId!,
        triggerProductId: productId,
        triggerProductEventId: event.eventId,
        originVariantId: variant.id,
      );
      await _eventStore.appendAndApply(
        SyncEvent(
          eventId: _uuid.v4(),
          aggregateType: RecursoInventarioDescartadoPayload.aggregateType,
          aggregateId: item.id,
          eventType: RecursoInventarioDescartadoPayload.eventType,
          deviceId: _commandContext.deviceId,
          userId: _commandContext.userId,
          baseVersion: item.version,
          baseServerSequence: item.lastServerSequence,
          createdAtLocal: event.createdAtLocal,
          deliveryStatus: RecursoInventarioDescartadoPayload.deliveryStatus,
          payload: discardPayload.toJson(),
        ),
        refs: discardPayload.refs(item.id),
      );
      discarded.add(item.id);
    }
    return ProductoInventoryUpdateResult(
      discardedInventoryItemIds: discarded,
      preservationReasons: reasons,
    );
  }

  Future<void> eliminarArticulo({
    required String productId,
    required String baseEventId,
  }) => _runInTransaction(
    () => _eliminarArticulo(productId: productId, baseEventId: baseEventId),
  );

  Future<void> _eliminarArticulo({
    required String productId,
    required String baseEventId,
  }) async {
    final product = await _obtenerBaseEdicion(productId);
    if (product.lastEventId != baseEventId) {
      throw StateError('El artículo cambió. Vuelve a abrirlo.');
    }
    final before = await _snapshotForEdit(productId);
    final variants = await _productoProjectionStore!.findVariantsByProductId(
      productId,
    );
    final payload = ProductoActualizadoPayload(
      baseEventId: baseEventId,
      before: before,
      after: before,
      deleteProduct: true,
    );
    await _eventStore.appendAndApply(
      SyncEvent(
        eventId: _uuid.v4(),
        aggregateType: ProductoActualizadoPayload.aggregateType,
        aggregateId: productId,
        eventType: ProductoActualizadoPayload.eventType,
        deviceId: _commandContext.deviceId,
        userId: _commandContext.userId,
        baseVersion: product.version,
        baseServerSequence:
            (await _syncedEventHistory.eventById(
                  product.lastEventId!,
                ))?.deliveryStatus ==
                'pending'
            ? null
            : product.lastServerSequence,
        createdAtLocal: DateTime.now(),
        payload: payload.toJson(),
      ),
      refs: [
        LocalEventRef.affects(refType: 'product', refId: productId),
        for (final v in variants) ...[
          LocalEventRef.affects(refType: 'product_variant', refId: v.id),
          LocalEventRef.affects(refType: 'recipe', refId: v.id),
        ],
        ..._supplierRefs([before]),
      ],
    );
  }

  Future<void> crearArticulo(CrearArticuloCommand command) =>
      _runInTransaction(() => _crearArticulo(command));

  Future<void> _crearArticulo(CrearArticuloCommand command) async {
    final article = await _prepareArticulo(command);
    final event = _creationEvent(article);
    await _appendArticulo(article, event);
  }

  /// Prepara todo antes de escribir. Recursos de todo el lote preceden a los
  /// productos y el adaptador debe garantizar una sola transacción local.
  Future<void> crearArticulosLote(List<CrearArticuloCommand> commands) =>
      _runInTransaction(() => _crearArticulosLote(commands));

  Future<void> _crearArticulosLote(List<CrearArticuloCommand> commands) async {
    if (commands.isEmpty) return;
    if (_eventStore is! LocalAtomicEventBatchStore) {
      throw StateError(
        'La carga por lotes requiere un almacén de eventos transaccional.',
      );
    }
    final articles = <_PreparedArticulo>[];
    for (final command in commands) {
      articles.add(await _prepareArticulo(command));
    }
    final entries = [
      for (final article in articles)
        ..._articleAppends(article, _creationEvent(article)),
    ];
    await _eventStore.appendAndApplyAll([
      ...entries.where(
        (entry) =>
            entry.event.eventType == RecursoInventarioCreadoPayload.eventType,
      ),
      ...entries.where(
        (entry) => entry.event.eventType == ProductoCreadoPayload.eventType,
      ),
    ]);
  }

  SyncEvent _creationEvent(_PreparedArticulo article) {
    return SyncEvent(
      eventId: article.eventId,
      aggregateType: ProductoCreadoPayload.aggregateType,
      aggregateId: article.productId,
      eventType: ProductoCreadoPayload.eventType,
      deviceId: _commandContext.deviceId,
      userId: _commandContext.userId,
      baseVersion: 1,
      createdAtLocal: DateTime.now(),
      payload: article.payload.toJson(),
    );
  }

  Future<_PreparedArticulo> _prepareArticulo(
    CrearArticuloCommand command, {
    String? existingProductId,
    ProductoCreadoPayload? before,
    List<String?>? existingVariantIds,
  }) async {
    final nombre = NombreProducto.fromInput(command.nombre);
    final saleConfiguration = await _validateSaleConfiguration(
      command.saleConfiguration,
    );
    final variants = await _normalizeVariants(command, saleConfiguration);
    final categoriaId = _normalizeOptional(command.categoriaId);
    final dependency = categoriaId == null
        ? null
        : await _categoryDependency(categoriaId);
    final productId = existingProductId ?? _uuid.v4();
    final variantIds = _resolveVariantIds(variants.length, existingVariantIds);
    final eventId = _uuid.v4();
    final inventoryBindings = await _prepareInventoryBindings(
      variants,
      variantIds,
      before,
      saleConfiguration,
    );
    final inventoryDependencies = await _resolveInventoryDependencies(
      variants,
      variantIds,
      inventoryBindings,
      before,
    );
    final variantPayloads = _buildVariantPayloads(
      variants,
      variantIds,
      inventoryBindings,
      before,
    );
    final supplierDependencies = await _supplierDependencies(variantPayloads);
    final payload = ProductoCreadoPayload.create(
      nombre: nombre.value,
      categoriaId: categoriaId,
      saleConfiguration: saleConfiguration,
      variantes: variantPayloads,
      dependenciasProveedores: supplierDependencies,
      dependenciaCategoria: dependency,
      dependenciasInventario: inventoryDependencies,
    );
    return _PreparedArticulo(
      productId: productId,
      eventId: eventId,
      payload: payload,
      inventoryBindings: inventoryBindings,
    );
  }

  Future<List<_NormalizedVariant>> _normalizeVariants(
    CrearArticuloCommand command,
    SaleConfiguration saleConfiguration,
  ) async {
    final capturedVariants = command.variantes.isEmpty
        ? [
            CrearArticuloVarianteCommand(
              nombre: null,
              precioVenta: command.precioVenta ?? '',
              costoEstandar: null,
            ),
          ]
        : command.variantes;
    final normalizedVariants = <_NormalizedVariant>[];
    final nameKeys = <String>{};
    for (final captured in capturedVariants) {
      final name = NombreVariante.fromInput(captured.nombre);
      final nameKey = name.nameKey;
      if (nameKey != null && !nameKeys.add(nameKey)) {
        throw ArgumentError.value(
          captured.nombre,
          'nombreVariante',
          'Los nombres de variantes no pueden repetirse.',
        );
      }
      final directInventory = await _normalizeInventoryTracking(
        captured,
        saleConfiguration,
      );
      final recipeComponents = await _normalizeRecipeComponents(captured);
      if (directInventory != null && recipeComponents.isNotEmpty) {
        throw const FormatException(
          'Una variante no puede usar seguimiento directo y receta simultáneamente.',
        );
      }
      normalizedVariants.add(
        _NormalizedVariant(
          nombre: name.value,
          precioVentaMenor: PrecioVenta.fromInput(
            captured.precioVenta,
          ).unidadMenor,
          costoEstandarMenor: CostoEstandar.fromInput(
            captured.costoEstandar,
          )?.unidadMenor,
          codigoBarras: CodigoBarras.fromInput(captured.codigoBarras).value,
          inventory: directInventory,
          recipeComponents: recipeComponents,
          proveedores: ProveedorVariante.canonical(captured.proveedores),
          existingInventoryItemId: _normalizeOptional(
            captured.existingInventoryItemId,
          ),
        ),
      );
    }
    return normalizedVariants;
  }

  List<String> _resolveVariantIds(
    int variantCount,
    List<String?>? existingVariantIds,
  ) {
    final variantIds =
        existingVariantIds?.map((id) => id ?? _uuid.v4()).toList() ??
        List.generate(variantCount, (_) => _uuid.v4(), growable: false);
    if (variantIds.length != variantCount ||
        variantIds.toSet().length != variantIds.length) {
      throw const FormatException(
        'Los identificadores de variantes deben ser únicos y coincidir con el formulario.',
      );
    }
    return variantIds;
  }

  Future<List<_InventoryBinding>> _prepareInventoryBindings(
    List<_NormalizedVariant> normalizedVariants,
    List<String> variantIds,
    ProductoCreadoPayload? before,
    SaleConfiguration saleConfiguration,
  ) async {
    final inventoryBindings = <_InventoryBinding>[];
    for (var index = 0; index < normalizedVariants.length; index++) {
      final inventory = normalizedVariants[index].inventory;
      if (inventory == null) continue;
      final variantId = variantIds[index];
      final previous = before?.variantes
          .where((v) => v.id == variantId)
          .firstOrNull;

      final resolution =
          previous == null &&
              normalizedVariants[index].existingInventoryItemId == null
          ? const RecursoNuevoResultado()
          : await _resolveResource(
              variantId: variantId,
              currentInventoryItemId: previous?.inventoryItemId,
              inventory: inventory,
              saleConfiguration: saleConfiguration,
              selectedInventoryItemId:
                  normalizedVariants[index].existingInventoryItemId,
            );

      switch (resolution) {
        case RecursoRecuperableResultado(:final inventoryItemId):
          // Recuperar o conservar nunca crea existencia inicial: el saldo ya
          // existe y se modifica solo con movimientos (SEG-05, SEG-18).
          if (inventory.initialQuantityAtomic != null) {
            throw const FormatException(
              'La existencia se modifica mediante movimientos de inventario.',
            );
          }
          inventoryBindings.add(
            _InventoryBinding(
              variantIndex: index,
              inventoryItemId: inventoryItemId,
              variantId: variantId,
              creationEventId: null,
              movementId: null,
              unit: inventory.unit,
              initialQuantityAtomic: null,
            ),
          );
        case RecursoNuevoResultado():
          if (previous?.inventoryItemId != null) {
            throw const FormatException(
              'La existencia se modifica mediante movimientos de inventario.',
            );
          }
          inventoryBindings.add(
            _InventoryBinding(
              variantIndex: index,
              inventoryItemId: _uuid.v4(),
              variantId: variantId,
              creationEventId: _uuid.v4(),
              movementId: inventory.initialQuantityAtomic == null
                  ? null
                  : _uuid.v4(),
              unit: inventory.unit,
              initialQuantityAtomic: inventory.initialQuantityAtomic,
            ),
          );
        case RecursoNoDisponibleResultado(:final motivo):
          throw FormatException(motivo);
        case RecursoSeleccionRequeridaResultado(:final motivo):
          throw FormatException(motivo);
      }
    }
    return inventoryBindings;
  }

  /// Decide el recurso de una variante aplicando el §3.1 del contrato.
  ///
  /// La resolución ocurre al guardar, no al abrir el editor: lo observado en
  /// pantalla puede quedarse viejo, y el command manda. `before` y un posible
  /// descarte ya aplicado son las dos piezas de historial que se permite
  /// consultar aquí; el resto viene de los puertos de memoria y procedencia.
  Future<RecursoRecuperacionResultado> _resolveResource({
    required String variantId,
    required String? currentInventoryItemId,
    required _NormalizedInventory inventory,
    required SaleConfiguration saleConfiguration,
    required String? selectedInventoryItemId,
  }) async {
    final trackingStore = _variantInventoryTrackingStore;
    final inventoryStore = _inventoryProjectionStore;
    final memoryStore = _variantInventoryMemoryStore;
    if (trackingStore == null ||
        inventoryStore == null ||
        memoryStore == null) {
      // Sin los puertos de seguimiento no se puede decidir con seguridad. Antes
      // este camino creaba un recurso nuevo por variante; ahora falla en lugar de
      // dejar datos duplicados.
      throw StateError(
        'No se configuró la resolución de recursos de inventario.',
      );
    }
    final resolver = InventoryResourceResolver(
      memoryStore: memoryStore,
      trackingStore: trackingStore,
      inventoryStore: inventoryStore,
    );
    return resolver.resolve(
      variantId: variantId,
      currentInventoryItemId: currentInventoryItemId,
      requiredUnitId: inventory.unit.id,
      saleConfiguration: saleConfiguration,
      selectedInventoryItemId: selectedInventoryItemId,
    );
  }

  Future<List<ProductoCreadoInventarioDependencia>>
  _resolveInventoryDependencies(
    List<_NormalizedVariant> normalizedVariants,
    List<String> variantIds,
    List<_InventoryBinding> inventoryBindings,
    ProductoCreadoPayload? before,
  ) async {
    final inventoryDependencies = <String, ProductoCreadoInventarioDependencia>{
      for (final binding in inventoryBindings)
        binding.inventoryItemId: ProductoCreadoInventarioDependencia(
          refId: binding.inventoryItemId,
          dependsOnEventId: binding.creationEventId,
        ),
      for (final variant in normalizedVariants)
        for (final component in variant.recipeComponents)
          component.inventoryItemId: ProductoCreadoInventarioDependencia(
            refId: component.inventoryItemId,
            dependsOnEventId: component.dependsOnEventId,
          ),
    };
    // Un recurso recuperado o seleccionado puede tener su alta aún pendiente de
    // aceptar por el servidor: se declara como dependencia normal y el push
    // espera su aceptación antes de enviar el producto (contrato §3.1 y §6.2).
    for (final binding in inventoryBindings.where((b) => !b.creaRecurso)) {
      inventoryDependencies[binding.inventoryItemId] =
          ProductoCreadoInventarioDependencia(
            refId: binding.inventoryItemId,
            dependsOnEventId: await _pendingCreationDependency(
              binding.inventoryItemId,
            ),
          );
    }
    return inventoryDependencies.values.toList(growable: false);
  }

  /// Evento de alta que debe aceptarse antes de empujar un producto que
  /// depende del recurso, o `null` si el alta ya está aceptada o no existe.
  Future<String?> _pendingCreationDependency(String inventoryItemId) async {
    final item = await _inventoryProjectionStore!.findItemById(inventoryItemId);
    if (item == null) {
      throw StateError('El recurso de inventario no existe.');
    }
    final createdEventId = item.createdEventId;
    if (createdEventId == null) return null;
    final creation = await _syncedEventHistory.eventById(createdEventId);
    return creation?.deliveryStatus == 'pending' ? creation!.eventId : null;
  }

  List<ProductoCreadoVariante> _buildVariantPayloads(
    List<_NormalizedVariant> normalizedVariants,
    List<String> variantIds,
    List<_InventoryBinding> inventoryBindings,
    ProductoCreadoPayload? before,
  ) {
    final inventoryByVariant = {
      for (final binding in inventoryBindings) binding.variantIndex: binding,
    };
    return [
      for (var index = 0; index < normalizedVariants.length; index++)
        ProductoCreadoVariante.create(
          id: variantIds[index],
          nombre: normalizedVariants[index].nombre,
          precioVentaMenor: normalizedVariants[index].precioVentaMenor,
          costoEstandarMenor: normalizedVariants[index].costoEstandarMenor,
          codigoBarras: normalizedVariants[index].codigoBarras,
          // Una binding existe siempre que la variante conserva o recupera
          // seguimiento directo; su `inventoryItemId` manda sobre `before`,
          // porque la resolución del command ocurre al guardar.
          inventoryItemId:
              inventoryByVariant[index]?.inventoryItemId ??
              (normalizedVariants[index].inventory == null
                  ? null
                  : before?.variantes
                        .where((v) => v.id == variantIds[index])
                        .firstOrNull
                        ?.inventoryItemId),
          componentesReceta: [
            for (final component in normalizedVariants[index].recipeComponents)
              ProductoCreadoComponenteReceta.create(
                inventoryItemId: component.inventoryItemId,
                quantityAtomic: component.quantityAtomic,
              ),
          ],
          proveedores: _variantSuppliers(
            normalizedVariants[index],
            before?.variantes
                .where((v) => v.id == variantIds[index])
                .firstOrNull,
          ),
          orden: index,
        ),
    ];
  }

  List<ProductoProveedorPrecio>? _variantSuppliers(
    _NormalizedVariant variant,
    ProductoCreadoVariante? previous,
  ) {
    final captured = variant.proveedores;
    if (captured == null) {
      return previous?.proveedores ??
          (_proveedorProjectionStore != null ? const [] : null);
    }
    final prior = {
      for (final s in previous?.proveedores ?? <ProductoProveedorPrecio>[])
        s.supplierId: s,
    };
    return [
      for (final s in captured)
        ProductoProveedorPrecio(
          supplierId: s.proveedorId,
          quotedPriceMinor: s.precioInformadoMenor,
          quotedAtMs:
              prior[s.proveedorId]?.quotedPriceMinor == s.precioInformadoMenor
              ? prior[s.proveedorId]!.quotedAtMs
              : s.fechaInformadaMs,
        ),
    ];
  }

  Future<List<ProductoProveedorDependencia>> _supplierDependencies(
    List<ProductoCreadoVariante> variants,
  ) async {
    final ids = {
      for (final v in variants)
        for (final s in v.proveedores ?? <ProductoProveedorPrecio>[])
          s.supplierId,
    };
    final result = <ProductoProveedorDependencia>[];
    for (final id in ids) {
      final supplier = await _proveedorProjectionStore?.findById(id);
      if (supplier == null) throw StateError('No existe el proveedor $id.');
      String? dependency;
      if (supplier.lastServerSequence == null) {
        final creation = supplier.createdEventId == null
            ? null
            : await _syncedEventHistory.eventById(supplier.createdEventId!);
        if (creation == null ||
            creation.eventType != ProveedorCreadoPayload.eventType ||
            creation.aggregateId != id) {
          throw StateError('No se encontró el alta del proveedor $id.');
        }
        switch (creation.deliveryStatus) {
          case 'pending':
            dependency = creation.eventId;
          case 'not_required':
            if (!_isStandalone) {
              throw StateError(
                'El proveedor local requiere una importación explícita.',
              );
            }
          case 'delivered':
            break;
          default:
            throw StateError('El alta del proveedor $id no fue aceptada.');
        }
      }
      result.add(
        ProductoProveedorDependencia(refId: id, dependsOnEventId: dependency),
      );
    }
    return result;
  }

  List<LocalEventRef> _supplierRefs(List<ProductoCreadoPayload> states) {
    final variantIds = {
      for (final state in states)
        for (final v in state.variantes)
          if (v.proveedores != null) v.id,
    }.toList()..sort();
    final supplierIds = {
      for (final state in states) ...state.supplierIds,
    }.toList()..sort();
    return [
      for (final id in variantIds)
        LocalEventRef.affects(refType: 'variant_suppliers', refId: id),
      for (final id in supplierIds)
        LocalEventRef.uses(refType: 'supplier', refId: id),
    ];
  }

  List<LocalEventRef> _buildArticleRefs({
    required String productId,
    required ProductoCreadoPayload payload,
    ProductoActualizadoPayload? updatePayload,
  }) {
    final referencedInventoryItemIds = <String>{
      for (final variant in payload.variantes) ...[
        if (variant.inventoryItemId != null) variant.inventoryItemId!,
        ...variant.componentesReceta.map(
          (component) => component.inventoryItemId,
        ),
      ],
    }.toList()..sort();

    final categoriaId = payload.categoriaId;
    final saleConfiguration = payload.saleConfiguration;
    return [
      LocalEventRef.affects(refType: 'product', refId: productId),
      ..._supplierRefs([
        if (updatePayload != null) updatePayload.before,
        payload,
      ]),
      if (updatePayload != null)
        for (final v in updatePayload.removedVariants) ...[
          LocalEventRef.affects(refType: 'product_variant', refId: v.id),
          LocalEventRef.affects(refType: 'recipe', refId: v.id),
        ],
      for (var index = 0; index < payload.variantes.length; index++) ...[
        LocalEventRef.affects(
          refType: 'product_variant',
          refId: payload.variantes[index].id,
        ),
        if (updatePayload != null)
          LocalEventRef.affects(
            refType: 'recipe',
            refId: payload.variantes[index].id,
          ),
        if (payload.variantes[index].nameKey case final nameKey?)
          LocalEventRef.requiresUnique(
            refType: 'product_variant_name',
            refId: _variantNameRefId(productId, nameKey),
          ),
      ],
      for (final inventoryItemId in referencedInventoryItemIds)
        LocalEventRef.uses(refType: 'inventory_item', refId: inventoryItemId),
      if (categoriaId != null)
        LocalEventRef.uses(refType: 'category', refId: categoriaId),
      if (saleConfiguration is MeasuredSaleConfiguration)
        LocalEventRef.uses(
          refType: 'unit',
          refId: saleConfiguration.saleUnitId,
        ),
    ];
  }

  Future<void> _appendArticulo(
    _PreparedArticulo article,
    SyncEvent event, {
    ProductoActualizadoPayload? updatePayload,
  }) {
    return _eventStore.appendAndApplyAll(
      _articleAppends(article, event, updatePayload: updatePayload),
    );
  }

  List<LocalEventAppend> _articleAppends(
    _PreparedArticulo article,
    SyncEvent event, {
    ProductoActualizadoPayload? updatePayload,
  }) {
    return [
      // Solo las variantes que crean recurso emiten `recurso_inventario_creado`.
      // Recuperar o conservar un recurso existente no genera alta, ni balance ni
      // `initial_balance` nuevos (contrato §3.2).
      for (final binding in article.inventoryBindings.where(
        (b) => b.creaRecurso,
      ))
        _inventoryCreationAppend(
          binding: binding,
          productName: article.payload.nombre,
          variantName: article.payload.variantes[binding.variantIndex].nombre,
          createdAt: event.createdAtLocal,
        ),
      LocalEventAppend(
        event: event,
        refs: _buildArticleRefs(
          productId: article.productId,
          payload: article.payload,
          updatePayload: updatePayload,
        ),
      ),
    ];
  }

  Future<_NormalizedInventory?> _normalizeInventoryTracking(
    CrearArticuloVarianteCommand captured,
    SaleConfiguration saleConfiguration,
  ) async {
    final unitId = _normalizeOptional(captured.inventoryUnitId);
    final initialQuantity = _normalizeOptional(captured.initialStockQuantity);
    if (unitId == null) {
      if (initialQuantity != null) {
        throw ArgumentError.value(
          captured.initialStockQuantity,
          'initialStockQuantity',
          'La existencia inicial requiere seguimiento de inventario.',
        );
      }
      return null;
    }

    final unit = await _unidadInventarioRepository.obtenerUnidadPorId(unitId);
    if (unit == null || !unit.activa) {
      throw StateError('La unidad del inventario no existe o está inactiva.');
    }
    switch (saleConfiguration) {
      case UnitSaleConfiguration():
        if (unit.dimension != DimensionUnidad.count ||
            unit.factorAtomico != 1) {
          throw StateError(
            'Una variante vendida por unidad debe controlar existencias en piezas.',
          );
        }
      case MeasuredSaleConfiguration():
        final saleUnit = await _unidadInventarioRepository.obtenerUnidadPorId(
          saleConfiguration.saleUnitId,
        );
        if (saleUnit == null || unit.dimension != saleUnit.dimension) {
          throw StateError(
            'La unidad de inventario debe tener la misma dimensión que la venta.',
          );
        }
    }
    return _NormalizedInventory(
      unit: unit,
      initialQuantityAtomic: initialQuantity == null
          ? null
          : switch (_quantityCodec.parseNonNegativeAtomic(
              initialQuantity,
              unit,
            )) {
              0 => null,
              final quantity => quantity,
            },
    );
  }

  Future<List<_NormalizedRecipeComponent>> _normalizeRecipeComponents(
    CrearArticuloVarianteCommand captured,
  ) async {
    if (captured.recipeComponents.isEmpty) return const [];
    final inventoryStore = _inventoryProjectionStore;
    if (inventoryStore == null) {
      throw StateError(
        'No se configuró la proyección de inventario para crear recetas.',
      );
    }
    final ids = <String>{};
    final normalized = <_NormalizedRecipeComponent>[];
    for (final component in captured.recipeComponents) {
      final inventoryItemId = _normalizeOptional(component.inventoryItemId);
      if (inventoryItemId == null || !ids.add(inventoryItemId)) {
        throw const FormatException(
          'Los recursos de una receta deben existir y no pueden repetirse.',
        );
      }
      final item = await inventoryStore.findItemById(inventoryItemId);
      if (item == null || !item.active) {
        throw StateError(
          'El recurso de inventario $inventoryItemId no existe o está inactivo.',
        );
      }
      final unit = await _unidadInventarioRepository.obtenerUnidadPorId(
        item.defaultUnitId,
      );
      if (unit == null || !unit.activa) {
        throw StateError(
          'La unidad del recurso $inventoryItemId no existe o está inactiva.',
        );
      }
      normalized.add(
        _NormalizedRecipeComponent(
          inventoryItemId: inventoryItemId,
          quantityAtomic: _quantityCodec.parsePositiveAtomic(
            component.quantity,
            unit,
          ),
          dependsOnEventId: await _inventoryDependency(item),
        ),
      );
    }
    normalized.sort(
      (left, right) => left.inventoryItemId.compareTo(right.inventoryItemId),
    );
    return List.unmodifiable(normalized);
  }

  Future<String?> _inventoryDependency(InventoryItemProjection item) async {
    if (item.lastServerSequence != null) return null;
    final createdEventId = item.createdEventId;
    if (createdEventId == null) {
      throw StateError('El recurso ${item.id} no tiene evento de creación.');
    }
    final createdEvent = await _syncedEventHistory.eventById(createdEventId);
    if (createdEvent == null ||
        createdEvent.eventType != RecursoInventarioCreadoPayload.eventType ||
        createdEvent.aggregateId != item.id) {
      throw StateError(
        'No se encontró el evento de creación del recurso ${item.id}.',
      );
    }
    return switch (createdEvent.deliveryStatus) {
      'pending' => createdEvent.eventId,
      'delivered' || 'not_required' => null,
      'conflict' || 'rejected' => throw StateError(
        'La creación del recurso ${item.id} no fue aceptada.',
      ),
      final status => throw StateError(
        'Estado de creación de recurso no soportado: $status',
      ),
    };
  }

  LocalEventAppend _inventoryCreationAppend({
    required _InventoryBinding binding,
    required String productName,
    required String? variantName,
    required DateTime createdAt,
  }) {
    final movement = binding.initialQuantityAtomic == null
        ? null
        : InitialInventoryMovementPayload.create(
            movementId: binding.movementId!,
            movementType: TipoMovimientoInventario.initialBalance,
            quantityDeltaAtomic: binding.initialQuantityAtomic!,
          );
    final payload = RecursoInventarioCreadoPayload.create(
      inventoryItemId: binding.inventoryItemId,
      name: _inventoryResourceName(productName, variantName),
      defaultUnitId: binding.unit.id,
      // Procedencia explícita: es lo que permite distinguir más adelante un
      // recurso autogenerado de uno independiente o legado, y es condición 1 de
      // la elegibilidad de descarte. Recursos independientes la omiten.
      originVariantId: binding.variantId,
      initialMovement: movement,
    );
    final event = SyncEvent(
      eventId: binding.creationEventId!,
      aggregateType: RecursoInventarioCreadoPayload.aggregateType,
      aggregateId: binding.inventoryItemId,
      eventType: RecursoInventarioCreadoPayload.eventType,
      deviceId: _commandContext.deviceId,
      userId: _commandContext.userId,
      baseVersion: 1,
      createdAtLocal: createdAt,
      payload: payload.toJson(),
    );
    return LocalEventAppend(
      event: event,
      refs: [
        LocalEventRef.affects(
          refType: 'inventory_item',
          refId: binding.inventoryItemId,
        ),
        LocalEventRef.uses(refType: 'unit', refId: binding.unit.id),
        if (binding.movementId case final movementId?)
          LocalEventRef.affects(
            refType: 'inventory_movement',
            refId: movementId,
          ),
      ],
    );
  }

  String _inventoryResourceName(String productName, String? variantName) {
    final candidate = variantName == null
        ? productName
        : '$productName · $variantName';
    return String.fromCharCodes(candidate.runes.take(160));
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

  String _variantNameRefId(String productId, String nameKey) {
    final encoded = base64Url.encode(utf8.encode(nameKey)).replaceAll('=', '');
    return '$productId:$encoded';
  }
}

class _PreparedArticulo {
  const _PreparedArticulo({
    required this.productId,
    required this.eventId,
    required this.payload,
    required this.inventoryBindings,
  });

  final String productId;
  final String eventId;
  final ProductoCreadoPayload payload;
  final List<_InventoryBinding> inventoryBindings;
}

class _NormalizedVariant {
  const _NormalizedVariant({
    required this.nombre,
    required this.precioVentaMenor,
    required this.costoEstandarMenor,
    required this.codigoBarras,
    required this.inventory,
    required this.recipeComponents,
    this.existingInventoryItemId,
    this.proveedores,
  });

  final String? nombre;
  final int precioVentaMenor;
  final int? costoEstandarMenor;
  final String? codigoBarras;
  final _NormalizedInventory? inventory;
  final List<_NormalizedRecipeComponent> recipeComponents;
  final List<ProveedorVariante>? proveedores;

  /// Recurso existente que la persona usuaria eligió explícitamente para
  /// recuperar, por ejemplo al resolver un legado ambiguo. Es una intención de
  /// comando validada por el resolver, no un campo de pantalla ni un CRUD.
  final String? existingInventoryItemId;
}

class _NormalizedRecipeComponent {
  const _NormalizedRecipeComponent({
    required this.inventoryItemId,
    required this.quantityAtomic,
    required this.dependsOnEventId,
  });

  final String inventoryItemId;
  final int quantityAtomic;
  final String? dependsOnEventId;
}

class _NormalizedInventory {
  const _NormalizedInventory({
    required this.unit,
    required this.initialQuantityAtomic,
  });

  final UnidadInventario unit;
  final int? initialQuantityAtomic;
}

class _InventoryBinding {
  const _InventoryBinding({
    required this.variantIndex,
    required this.variantId,
    required this.inventoryItemId,
    required this.creationEventId,
    required this.movementId,
    required this.unit,
    required this.initialQuantityAtomic,
  });

  final int variantIndex;
  final String variantId;
  final String inventoryItemId;

  /// Evento de alta del recurso. `null` cuando el recurso se recupera o se
  /// conserva: en ese caso no se emite `recurso_inventario_creado`, y por eso
  /// no hay ni balance ni `initial_balance` nuevos.
  final String? creationEventId;
  final String? movementId;
  final UnidadInventario unit;
  final int? initialQuantityAtomic;

  /// Solo las binding que crean el recurso generan un evento de alta.
  bool get creaRecurso => creationEventId != null;
}
