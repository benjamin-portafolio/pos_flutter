import 'package:uuid/uuid.dart';

import '../../../domain/articulos/sale_configuration.dart';
import '../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../domain/inventario/unidad_inventario.dart';
import '../../../domain/repositories/unidad_inventario_repository.dart';
import '../../../domain/ventas/sale_status.dart';
import '../../sync/local_event_store.dart';
import '../../sync/models/sync_event.dart';
import '../../sync/payloads/producto_agregado_borrador_payload.dart';
import '../../sync/payloads/sale_item_snapshot.dart';
import '../../sync/payloads/venta_borrador_limpiada_payload.dart';
import '../../sync/projections/producto_projection_store.dart';
import '../../sync/projections/sale_draft_projection_store.dart';
import '../../sync/projections/sale_item_projection.dart';
import 'agregar_producto_borrador_command.dart';
import 'limpiar_venta_borrador_command.dart';
import '../local_command_context.dart';

class VentaBorradorCommandService {
  VentaBorradorCommandService({
    required this.store,
    required this.products,
    required this.units,
    required this.events,
    required this.context,
  });
  final SaleDraftProjectionStore store;
  final ProductoProjectionStore products;
  final UnidadInventarioRepository units;
  final LocalEventStore events;
  final LocalCommandContext context;
  final _uuid = const Uuid();

  Future<void> limpiar(LimpiarVentaBorradorCommand command) =>
      store.atomic(() async {
        final saleId = command.saleId.trim();
        if (saleId.isEmpty ||
            context.userId.trim().isEmpty ||
            context.deviceId.trim().isEmpty) {
          throw const FormatException(
            'La venta y el contexto local son obligatorios.',
          );
        }
        final sale = await store.findById(saleId);
        if (sale == null) return;
        if (sale.userId != context.userId ||
            sale.deviceId != context.deviceId ||
            !sale.active ||
            sale.status != SaleStatus.borrador) {
          throw StateError('La venta no corresponde al borrador actual.');
        }
        final items = await store.items(saleId);
        final payload = VentaBorradorLimpiadaPayload(
          saleItemIds: items.map((item) => item.id).toList(),
        );
        final refs = [
          LocalEventRef.affects(refType: 'sale', refId: saleId),
          for (final id in payload.saleItemIds)
            LocalEventRef.affects(refType: 'sale_item', refId: id),
        ];
        await events.appendAndApply(
          SyncEvent(
            eventId: _uuid.v4(),
            aggregateType: VentaBorradorLimpiadaPayload.aggregateType,
            aggregateId: saleId,
            eventType: VentaBorradorLimpiadaPayload.eventType,
            deviceId: context.deviceId,
            userId: context.userId,
            baseVersion: sale.version,
            createdAtLocal: DateTime.now(),
            deliveryStatus: 'not_required',
            payload: payload.toJson(),
          ),
          refs: refs,
        );
      });

  Future<void> agregar(AgregarProductoBorradorCommand command) =>
      store.atomic(() async {
        final item = await _prepareDraftItem(command);
        final sale = await store.findDraft(context.userId, context.deviceId);
        final saleId = sale?.id ?? _uuid.v4();
        final lines = await store.items(saleId);
        final payload = _buildDraftLine(item.snapshot, lines);
        final refs = _buildDraftRefs(saleId, item, payload);
        await events.appendAndApply(
          SyncEvent(
            eventId: _uuid.v4(),
            aggregateType: ProductoAgregadoBorradorPayload.aggregateType,
            aggregateId: saleId,
            eventType: ProductoAgregadoBorradorPayload.eventType,
            deviceId: context.deviceId,
            userId: context.userId,
            baseVersion: sale?.version ?? 0,
            createdAtLocal: DateTime.now(),
            deliveryStatus: 'not_required',
            payload: payload.toJson(),
          ),
          refs: refs,
        );
      });

  Future<_PreparedDraftItem> _prepareDraftItem(
    AgregarProductoBorradorCommand command,
  ) async {
    final variant = await products.findVariantById(command.variantId.trim());
    if (variant == null || !variant.active) {
      throw StateError('La variante ya no está disponible.');
    }
    final product = await products.findProductById(variant.productoId);
    if (product == null || !product.active) {
      throw StateError('El artículo ya no está disponible.');
    }
    final config = product.saleConfiguration;
    final unit = config is MeasuredSaleConfiguration
        ? await units.obtenerUnidadPorId(config.saleUnitId)
        : null;
    final atomic = _readMeasuredQuantity(command, config, unit);
    final snapshot = SaleItemSnapshot(
      variantId: variant.id,
      productName: product.nombre,
      variantName: variant.nombre,
      saleMode: config is MeasuredSaleConfiguration ? 'measured' : 'unit',
      quantity: atomic == null ? 1 : null,
      measuredQuantityAtomic: atomic,
      unitPriceMinor: variant.precioVentaMenor,
      standardCostMinor: variant.costoEstandarMenor,
      priceReferenceQuantityAtomic: config.priceReferenceQuantityAtomic,
      unitCode: unit?.code,
      unitSymbol: unit?.simbolo,
      unitAtomicFactor: unit?.factorAtomico,
    );
    return _PreparedDraftItem(
      productId: product.id,
      unitId: unit?.id,
      snapshot: snapshot,
    );
  }

  int? _readMeasuredQuantity(
    AgregarProductoBorradorCommand command,
    SaleConfiguration config,
    UnidadInventario? unit,
  ) {
    int? atomic;
    if (config is MeasuredSaleConfiguration) {
      if (unit == null || !unit.activa || command.expectedUnitId != unit.id) {
        throw StateError(
          'La unidad de venta cambió o no está disponible. Vuelve a seleccionar el artículo.',
        );
      }
      atomic = const InventoryQuantityCodec().parsePositiveAtomic(
        command.measuredQuantity ?? '',
        unit,
      );
    } else if (command.measuredQuantity != null ||
        command.expectedUnitId != null) {
      throw StateError(
        'El modo de venta cambió. Vuelve a seleccionar el artículo.',
      );
    }
    return atomic;
  }

  ProductoAgregadoBorradorPayload _buildDraftLine(
    SaleItemSnapshot snapshot,
    List<SaleItemProjection> lines,
  ) {
    SaleItemProjection? existing;
    for (final line in lines) {
      if (line.active && line.snapshot.sameConditions(snapshot)) {
        existing = line;
        break;
      }
    }
    if (existing != null) snapshot = existing.snapshot.plus(snapshot);
    final itemId = existing?.id ?? _uuid.v4();
    final sortOrder =
        existing?.sortOrder ??
        lines.fold<int>(
              -1,
              (max, line) => line.sortOrder > max ? line.sortOrder : max,
            ) +
            1;
    return ProductoAgregadoBorradorPayload(
      saleItemId: itemId,
      sortOrder: sortOrder,
      item: snapshot,
    );
  }

  List<LocalEventRef> _buildDraftRefs(
    String saleId,
    _PreparedDraftItem item,
    ProductoAgregadoBorradorPayload payload,
  ) {
    final refs = [
      LocalEventRef.affects(refType: 'sale', refId: saleId),
      LocalEventRef.affects(refType: 'sale_item', refId: payload.saleItemId),
      LocalEventRef.uses(refType: 'product', refId: item.productId),
      LocalEventRef.uses(
        refType: 'product_variant',
        refId: item.snapshot.variantId,
      ),
      if (item.unitId case final unitId?)
        LocalEventRef.uses(refType: 'unit', refId: unitId),
    ];
    if (context.userId.trim().isEmpty ||
        context.deviceId.trim().isEmpty ||
        refs.any((ref) => ref.refId.trim().isEmpty)) {
      throw StateError('Las referencias y el contexto local son obligatorios.');
    }
    return refs;
  }
}

class _PreparedDraftItem {
  const _PreparedDraftItem({
    required this.productId,
    required this.unitId,
    required this.snapshot,
  });

  final String productId;
  final String? unitId;
  final SaleItemSnapshot snapshot;
}
