import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../domain/articulos/costo_estandar.dart';
import '../../domain/articulos/nombre_producto.dart';
import '../../domain/articulos/nombre_variante.dart';
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
        ),
      );
    }
    final categoriaId = _normalizeOptional(command.categoriaId);
    final saleConfiguration = await _validateSaleConfiguration(
      command.saleConfiguration,
    );
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
            esPredeterminada: index == 0,
            orden: index,
          ),
      ],
      dependenciaCategoria: dependency,
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

    await _eventStore.appendAndApply(
      event,
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
        ],
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
  });

  final String? nombre;
  final int precioVentaMenor;
  final int? costoEstandarMenor;
}
