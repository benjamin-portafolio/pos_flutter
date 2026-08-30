import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../domain/articulos/costo_estandar.dart';
import '../../domain/articulos/nombre_producto.dart';
import '../../domain/articulos/nombre_variante.dart';
import '../../domain/articulos/precio_venta.dart';
import '../../domain/articulos/sale_configuration.dart';
import '../../domain/inventario/dimension_unidad.dart';
import '../../domain/inventario/inventory_quantity_codec.dart';
import '../../domain/inventario/tipo_movimiento_inventario.dart';
import '../../domain/inventario/unidad_inventario.dart';
import '../../domain/repositories/unidad_inventario_repository.dart';
import '../sync/local_event_store.dart';
import '../sync/models/sync_event.dart';
import '../sync/payloads/categoria_creada_payload.dart';
import '../sync/payloads/producto_creado_payload.dart';
import '../sync/payloads/recurso_inventario_creado_payload.dart';
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
  static const _quantityCodec = InventoryQuantityCodec();

  Future<void> crearArticulo(CrearArticuloCommand command) async {
    final nombre = NombreProducto.fromInput(command.nombre);
    final saleConfiguration = await _validateSaleConfiguration(
      command.saleConfiguration,
    );
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
      normalizedVariants.add(
        _NormalizedVariant(
          nombre: name.value,
          precioVentaMenor: PrecioVenta.fromInput(
            captured.precioVenta,
          ).unidadMenor,
          costoEstandarMenor: CostoEstandar.fromInput(
            captured.costoEstandar,
          )?.unidadMenor,
          inventory: await _normalizeInventoryTracking(
            captured,
            saleConfiguration,
          ),
        ),
      );
    }
    final categoriaId = _normalizeOptional(command.categoriaId);
    final dependency = categoriaId == null
        ? null
        : await _categoryDependency(categoriaId);
    final productId = _uuid.v4();
    final variantIds = List.generate(
      normalizedVariants.length,
      (_) => _uuid.v4(),
      growable: false,
    );
    final eventId = _uuid.v4();
    final inventoryBindings = <_InventoryBinding>[];
    for (var index = 0; index < normalizedVariants.length; index++) {
      final inventory = normalizedVariants[index].inventory;
      if (inventory == null) continue;
      inventoryBindings.add(
        _InventoryBinding(
          variantIndex: index,
          inventoryItemId: _uuid.v4(),
          creationEventId: _uuid.v4(),
          movementId: inventory.initialQuantityAtomic == null
              ? null
              : _uuid.v4(),
          unit: inventory.unit,
          initialQuantityAtomic: inventory.initialQuantityAtomic,
        ),
      );
    }
    final inventoryByVariant = {
      for (final binding in inventoryBindings) binding.variantIndex: binding,
    };
    final payload = ProductoCreadoPayload.create(
      nombre: nombre.value,
      categoriaId: categoriaId,
      saleConfiguration: saleConfiguration,
      variantes: [
        for (var index = 0; index < normalizedVariants.length; index++)
          ProductoCreadoVariante.create(
            id: variantIds[index],
            nombre: normalizedVariants[index].nombre,
            precioVentaMenor: normalizedVariants[index].precioVentaMenor,
            costoEstandarMenor: normalizedVariants[index].costoEstandarMenor,
            inventoryItemId: inventoryByVariant[index]?.inventoryItemId,
            esPredeterminada: index == 0,
            orden: index,
          ),
      ],
      dependenciaCategoria: dependency,
      dependenciasInventario: [
        for (final binding in inventoryBindings)
          ProductoCreadoInventarioDependencia(
            refId: binding.inventoryItemId,
            dependsOnEventId: binding.creationEventId,
          ),
      ],
    );
    final event = SyncEvent(
      eventId: eventId,
      aggregateType: ProductoCreadoPayload.aggregateType,
      aggregateId: productId,
      eventType: ProductoCreadoPayload.eventType,
      deviceId: _commandContext.deviceId,
      userId: _commandContext.userId,
      baseVersion: 1,
      createdAtLocal: DateTime.now(),
      payload: payload.toJson(),
    );

    final createdAt = event.createdAtLocal;
    final entries = <LocalEventAppend>[
      for (final binding in inventoryBindings)
        _inventoryCreationAppend(
          binding: binding,
          productName: nombre.value,
          variantName: normalizedVariants[binding.variantIndex].nombre,
          createdAt: createdAt,
        ),
      LocalEventAppend(
        event: event,
        refs: [
          LocalEventRef.affects(refType: 'product', refId: productId),
          for (var index = 0; index < payload.variantes.length; index++) ...[
            LocalEventRef.affects(
              refType: 'product_variant',
              refId: payload.variantes[index].id,
            ),
            if (payload.variantes[index].nameKey case final nameKey?)
              LocalEventRef.requiresUnique(
                refType: 'product_variant_name',
                refId: _variantNameRefId(productId, nameKey),
              ),
            if (payload.variantes[index].inventoryItemId
                case final inventoryItemId?)
              LocalEventRef.uses(
                refType: 'inventory_item',
                refId: inventoryItemId,
              ),
          ],
          if (categoriaId != null)
            LocalEventRef.uses(refType: 'category', refId: categoriaId),
          if (saleConfiguration is MeasuredSaleConfiguration)
            LocalEventRef.uses(
              refType: 'unit',
              refId: saleConfiguration.saleUnitId,
            ),
        ],
      ),
    ];
    await _eventStore.appendAndApplyAll(entries);
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
      initialMovement: movement,
    );
    final event = SyncEvent(
      eventId: binding.creationEventId,
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

class _NormalizedVariant {
  const _NormalizedVariant({
    required this.nombre,
    required this.precioVentaMenor,
    required this.costoEstandarMenor,
    required this.inventory,
  });

  final String? nombre;
  final int precioVentaMenor;
  final int? costoEstandarMenor;
  final _NormalizedInventory? inventory;
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
    required this.inventoryItemId,
    required this.creationEventId,
    required this.movementId,
    required this.unit,
    required this.initialQuantityAtomic,
  });

  final int variantIndex;
  final String inventoryItemId;
  final String creationEventId;
  final String? movementId;
  final UnidadInventario unit;
  final int? initialQuantityAtomic;
}
