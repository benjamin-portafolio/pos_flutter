import '../../../domain/ventas/effective_sale_price.dart';
import 'sale_capture_conditions.dart';
import '../../../domain/ventas/measured_sale_conditions.dart';
import '../../sync/applied_local_event_reader.dart';
import '../../sync/offer_pricing_availability.dart';
import '../../sync/payloads/inventory_movement_payload.dart';
import '../../sync/payloads/tarifa_venta_borrador_cambiada_payload.dart';
import 'cambiar_tarifa_venta_borrador_command.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/articulos/sale_configuration.dart';
import '../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../domain/inventario/unidad_inventario.dart';
import '../../../domain/repositories/sale_draft_repository.dart';
import '../../../domain/repositories/unidad_inventario_repository.dart';
import '../../../domain/ventas/measured_sale_calculator.dart';
import '../../../domain/ventas/sale_status.dart';
import '../../sync/local_event_store.dart';
import '../../sync/models/sync_event.dart';
import '../../sync/payloads/producto_agregado_borrador_payload.dart';
import '../../sync/payloads/producto_actualizado_borrador_payload.dart';
import '../../sync/payloads/producto_eliminado_borrador_payload.dart';
import '../../sync/payloads/sale_item_snapshot.dart';
import '../../sync/payloads/venta_borrador_limpiada_payload.dart';
import '../../sync/projections/producto_projection_store.dart';
import '../../sync/projections/sale_draft_projection_store.dart';
import '../../sync/projections/sale_item_projection.dart';
import '../../sync/projections/sale_projection.dart';
import 'agregar_producto_borrador_command.dart';
import 'actualizar_producto_borrador_command.dart';
import 'eliminar_producto_borrador_command.dart';
import 'limpiar_venta_borrador_command.dart';
import '../local_command_context.dart';

class VentaBorradorCommandService {
  VentaBorradorCommandService({
    required this.store,
    required this.products,
    required this.units,
    required this.events,
    required this.context,
    this.drafts,
    this.offerPricing,
  });
  final SaleDraftProjectionStore store;
  final ProductoProjectionStore products;
  final UnidadInventarioRepository units;
  final LocalEventStore events;
  final LocalCommandContext context;
  final SaleDraftRepository? drafts;
  final OfferPricingAvailability? offerPricing;
  final _uuid = const Uuid();

  /// Sin escrituras: la UI confirma esta base y sus totales en la sesión 5.
  Future<TarifaVentaBorradorCambiadaPayload> previewTarifa(
    CambiarTarifaVentaBorradorCommand command,
  ) => store.atomic(() => _prepareTarifa(command));

  Future<TarifaVentaBorradorCambiadaPayload?> cambiarTarifa(
    CambiarTarifaVentaBorradorCommand command,
  ) => store.atomic(() async {
    InventoryMovementPayload.requiredUuidV4(
      command.operationId,
      'operation_id',
    );
    final applied = await (store as AppliedLocalEventReader).appliedLocalEvent(
      command.operationId,
    );
    if (applied != null) {
      if (applied.eventType != TarifaVentaBorradorCambiadaPayload.eventType ||
          applied.aggregateType !=
              TarifaVentaBorradorCambiadaPayload.aggregateType ||
          applied.aggregateId != command.saleId ||
          applied.userId != context.userId ||
          applied.deviceId != context.deviceId ||
          applied.baseVersion != command.expectedVersion) {
        throw StateError('Identidad de operación reutilizada.');
      }
      final p = TarifaVentaBorradorCambiadaPayload.fromJson(applied.payload);
      if (p.pricingMode != command.pricingMode ||
          p.expectedDraftEventId != command.expectedDraftEventId ||
          p.previousTotalMinor != command.expectedTotalMinor) {
        throw StateError('Intención distinta para la misma operación.');
      }
      return p;
    }
    final sale = await _tarifaBase(command);
    if ((sale?.pricingMode ?? 'normal') == command.pricingMode) {
      var total = BigInt.zero;
      for (final line in (await store.items(
        command.saleId,
      )).where((l) => l.active)) {
        if (!line.snapshot.sameConditions(
              line.snapshot.withPricingMode(command.pricingMode),
            ) ||
            (line.persistedTotalMinor != null &&
                line.persistedTotalMinor != line.snapshot.totalMinor)) {
          throw StateError(
            'Las condiciones de precio no coinciden con el borrador.',
          );
        }
        total += BigInt.from(line.snapshot.totalMinor);
      }
      if (total != BigInt.from(command.expectedTotalMinor)) {
        throw StateError('El total del borrador es incoherente.');
      }
      return null;
    }
    final payload = await _prepareTarifa(command);
    await offerPricing?.requireCompatible();
    final refs = [
      LocalEventRef.affects(refType: 'sale', refId: command.saleId),
      for (final l in payload.lines)
        LocalEventRef.affects(refType: 'sale_item', refId: l.id),
    ];
    if (refs.any((r) => r.refId.trim().isEmpty)) {
      throw StateError('Referencias inválidas.');
    }
    await events.appendAndApply(
      SyncEvent(
        eventId: command.operationId,
        aggregateType: TarifaVentaBorradorCambiadaPayload.aggregateType,
        aggregateId: command.saleId,
        eventType: TarifaVentaBorradorCambiadaPayload.eventType,
        deviceId: context.deviceId,
        userId: context.userId,
        baseVersion: command.expectedVersion,
        createdAtLocal: DateTime.now(),
        deliveryStatus: 'not_required',
        payload: payload.toJson(),
      ),
      refs: refs,
    );
    return payload;
  });

  Future<SaleProjection?> _tarifaBase(
    CambiarTarifaVentaBorradorCommand c,
  ) async {
    InventoryMovementPayload.requiredUuidV4(c.operationId, 'operation_id');
    InventoryMovementPayload.requiredUuidV4(c.saleId, 'sale_id');
    if (context.userId.trim().isEmpty ||
        context.deviceId.trim().isEmpty ||
        !['normal', 'offer'].contains(c.pricingMode) ||
        c.expectedVersion < 0 ||
        c.expectedVersion > SaleItemSnapshot.maxInteger ||
        c.expectedTotalMinor < 0 ||
        c.expectedTotalMinor > SaleItemSnapshot.maxInteger) {
      throw const FormatException('Contexto o tarifa inválidos.');
    }
    final s = await store.findById(c.saleId);
    if (await store.wasCleared(c.saleId) ||
        (s?.version ?? 0) != c.expectedVersion ||
        s?.lastEventId != c.expectedDraftEventId ||
        (s?.totalMinor ?? 0) != c.expectedTotalMinor ||
        (s != null &&
            (!s.active ||
                s.status != SaleStatus.borrador ||
                s.userId != context.userId ||
                s.deviceId != context.deviceId))) {
      throw StateError('El borrador cambió o ya fue cobrado.');
    }
    return s;
  }

  Future<TarifaVentaBorradorCambiadaPayload> _prepareTarifa(
    CambiarTarifaVentaBorradorCommand c,
  ) async {
    final sale = await _tarifaBase(c);
    final lines = (await store.items(c.saleId)).where((l) => l.active).toList();
    final after = [
      for (final l in lines)
        (
          id: l.id,
          sortOrder: l.sortOrder,
          before: l.snapshot,
          after: l.snapshot.withPricingMode(c.pricingMode),
        ),
    ];
    final total = after.fold(
      BigInt.zero,
      (sum, l) => sum + BigInt.from(l.after.totalMinor),
    );
    if (total > BigInt.from(SaleItemSnapshot.maxInteger)) {
      throw const FormatException('Total fuera de rango.');
    }
    return TarifaVentaBorradorCambiadaPayload(
      previousMode: sale?.pricingMode ?? 'normal',
      pricingMode: c.pricingMode,
      expectedDraftEventId: c.expectedDraftEventId,
      previousTotalMinor: c.expectedTotalMinor,
      totalMinor: total.toInt(),
      lines: after,
    );
  }

  Future<SaleCaptureConditions> prepararCaptura(String variantId) {
    final selected = drafts?.selectedDraftId;
    return store.atomic(() async {
      final sale = await _findSelectedDraft(selected);
      final saleId = sale?.id ?? selected ?? _uuid.v4();
      if (await store.wasCleared(saleId)) {
        throw StateError('La venta fue limpiada.');
      }
      final prepared = await _prepareDraftItem(
        AgregarProductoBorradorCommand(variantId: variantId),
        sale,
        preview: true,
      );
      final s = prepared.snapshot;
      final unit = prepared.unitId == null
          ? null
          : await units.obtenerUnidadPorId(prepared.unitId!);
      return SaleCaptureConditions(
        saleId: saleId,
        version: sale?.version ?? 0,
        draftEventId: sale?.lastEventId,
        pricingMode: sale?.pricingMode ?? 'normal',
        snapshot: s,
        measured: unit == null
            ? null
            : MeasuredSaleConditions(
                variantId: s.variantId,
                productName: s.productName,
                variantName: s.variantName,
                unit: unit,
                unitPriceMinor: s.unitPriceMinor,
                standardCostMinor: s.standardCostMinor,
                priceReferenceQuantityAtomic: s.priceReferenceQuantityAtomic!,
                consumptionConfigurationKey: s.consumptionConfigurationKey!,
                priceSnapshotVersion: s.priceSnapshotVersion,
                normalPriceMinorSnapshot: s.normalPriceMinorSnapshot,
                offerPriceMinorSnapshot: s.offerPriceMinorSnapshot,
                effectivePriceSource: s.effectivePriceSource,
                priceConfigurationEventId: s.priceConfigurationEventId,
              ),
      );
    });
  }

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
        if (command.expectedDraftEventId != null &&
            (command.expectedDraftEventId!.trim().isEmpty ||
                sale.lastEventId != command.expectedDraftEventId!.trim())) {
          throw StateError(
            'El borrador cambió; no se puede limpiar esta revisión.',
          );
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

  Future<void> agregar(AgregarProductoBorradorCommand command) {
    // Captura la selección antes de cualquier espera, incluida la transacción.
    final selectedId = command.expectedSaleId ?? drafts?.selectedDraftId;
    final selection = drafts?.selectedDraftId;
    return store.atomic(() async {
      if (command.expectedSaleId != null &&
          drafts != null &&
          selection != null &&
          selection != command.expectedSaleId) {
        throw StateError('Cambió la pestaña de captura.');
      }
      if (command.expectedSaleId == null &&
          [
            command.expectedVersion,
            command.expectedPricingMode,
            command.expectedDraftEventId,
            command.expectedPriceConfigurationEventId,
          ].any((v) => v != null)) {
        throw const FormatException(
          'La guarda de captura requiere venta y revisión completas.',
        );
      }
      if (command.expectedSaleId != null &&
          (command.expectedVersion == null ||
              command.expectedPricingMode == null ||
              command.expectedPriceConfigurationEventId == null)) {
        throw const FormatException('Faltan condiciones revisadas de captura.');
      }
      if (command.expectedSaleId != null &&
          drafts != null &&
          selection == null) {
        final current = await store.findDraft(context.userId, context.deviceId);
        if (current != null && current.id != command.expectedSaleId) {
          throw StateError('Cambió la venta mientras se capturaba.');
        }
      }
      final sale = await _findSelectedDraft(selectedId);
      final item = await _prepareDraftItem(command, sale);
      if (command.expectedSaleId != null &&
          (command.expectedSaleId != (sale?.id ?? selectedId) ||
              command.expectedDraftEventId != sale?.lastEventId ||
              command.expectedVersion != (sale?.version ?? 0) ||
              command.expectedPricingMode != (sale?.pricingMode ?? 'normal'))) {
        throw StateError(
          'La captura cambió. Revisa venta y tarifa antes de agregar.',
        );
      }
      final saleId = sale?.id ?? selectedId ?? _uuid.v4();
      if (sale == null && await store.wasCleared(saleId)) {
        throw StateError('La venta ya fue limpiada. Abre otra captura.');
      }
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
  }

  Future<void> actualizarProducto(ActualizarProductoBorradorCommand command) {
    final selectedId = drafts?.selectedDraftId;
    return store.atomic(() async {
      final saleItemId = command.saleItemId.trim();
      if (saleItemId.isEmpty) {
        throw const FormatException('El artículo de la venta es obligatorio.');
      }
      final sale = await _findSelectedDraft(selectedId);
      if (sale == null) {
        throw StateError('No hay una venta en preparación.');
      }
      final lines = await store.items(sale.id);
      SaleItemProjection? line;
      for (final candidate in lines) {
        if (candidate.id == saleItemId && candidate.active) {
          line = candidate;
          break;
        }
      }
      if (line == null) {
        throw StateError('El artículo ya no está en esta venta.');
      }
      final snapshot = await _updatedSnapshot(line.snapshot, command);
      final currentlyEquals =
          (snapshot.saleMode == 'unit' &&
              snapshot.quantity == line.snapshot.quantity) ||
          (snapshot.saleMode == 'measured' &&
              snapshot.measuredQuantityAtomic ==
                  line.snapshot.measuredQuantityAtomic);
      if (currentlyEquals) return; // Sin cambios: no registra un evento nuevo.
      final payload = ProductoActualizadoBorradorPayload(
        saleItemId: line.id,
        item: snapshot,
      );
      await events.appendAndApply(
        SyncEvent(
          eventId: _uuid.v4(),
          aggregateType: ProductoActualizadoBorradorPayload.aggregateType,
          aggregateId: sale.id,
          eventType: ProductoActualizadoBorradorPayload.eventType,
          deviceId: context.deviceId,
          userId: context.userId,
          baseVersion: sale.version,
          createdAtLocal: DateTime.now(),
          deliveryStatus: 'not_required',
          payload: payload.toJson(),
        ),
        refs: _draftEditRefs(sale.id, line.id),
      );
    });
  }

  Future<void> eliminarProducto(EliminarProductoBorradorCommand command) {
    final selectedId = drafts?.selectedDraftId;
    return store.atomic(() async {
      final saleItemId = command.saleItemId.trim();
      if (saleItemId.isEmpty) {
        throw const FormatException('El artículo de la venta es obligatorio.');
      }
      final sale = await _findSelectedDraft(selectedId);
      if (sale == null) {
        throw StateError('No hay una venta en preparación.');
      }
      final lines = await store.items(sale.id);
      var found = false;
      for (final line in lines) {
        if (line.id == saleItemId && line.active) {
          found = true;
          break;
        }
      }
      if (!found) throw StateError('El artículo ya no está en esta venta.');
      final payload = ProductoEliminadoBorradorPayload(saleItemId: saleItemId);
      await events.appendAndApply(
        SyncEvent(
          eventId: _uuid.v4(),
          aggregateType: ProductoEliminadoBorradorPayload.aggregateType,
          aggregateId: sale.id,
          eventType: ProductoEliminadoBorradorPayload.eventType,
          deviceId: context.deviceId,
          userId: context.userId,
          baseVersion: sale.version,
          createdAtLocal: DateTime.now(),
          deliveryStatus: 'not_required',
          payload: payload.toJson(),
        ),
        refs: _draftEditRefs(sale.id, saleItemId),
      );
    });
  }

  Future<SaleProjection?> _findSelectedDraft(String? selectedId) async {
    final sale = selectedId == null
        ? await store.findDraft(context.userId, context.deviceId)
        : await store.findById(selectedId);
    if (sale != null &&
        (!sale.active ||
            sale.status != SaleStatus.borrador ||
            sale.userId != context.userId ||
            sale.deviceId != context.deviceId)) {
      throw StateError('La venta no corresponde a una captura propia abierta.');
    }
    return sale;
  }

  Future<SaleItemSnapshot> _updatedSnapshot(
    SaleItemSnapshot snapshot,
    ActualizarProductoBorradorCommand command,
  ) async {
    if (snapshot.saleMode == 'unit') {
      if (command.measuredQuantity != null) {
        throw StateError('Una venta por piezas no admite medidas.');
      }
      final quantity = command.quantity;
      if (quantity == null ||
          quantity <= 0 ||
          quantity > SaleItemSnapshot.maxInteger) {
        throw const FormatException('Ingresa una cantidad mayor que cero.');
      }
      return snapshot.withQuantity(pieces: quantity);
    }
    if (command.quantity != null) {
      throw StateError('Una venta medida no admite piezas.');
    }
    final unit = await _draftUnit(snapshot);
    final atomic = const InventoryQuantityCodec().parsePositiveAtomic(
      command.measuredQuantity ?? '',
      unit,
    );
    return snapshot.withQuantity(atomic: atomic);
  }

  Future<UnidadInventario> _draftUnit(SaleItemSnapshot snapshot) async {
    final available = await units.obtenerUnidadesActivas();
    for (final unit in available) {
      if (unit.code == snapshot.unitCode) return unit;
    }
    throw StateError(
      'La unidad de venta cambió o no está disponible. Vuelve a seleccionar el artículo.',
    );
  }

  List<LocalEventRef> _draftEditRefs(String saleId, String saleItemId) {
    final refs = [
      LocalEventRef.affects(refType: 'sale', refId: saleId),
      LocalEventRef.affects(refType: 'sale_item', refId: saleItemId),
    ];
    if (context.userId.trim().isEmpty ||
        context.deviceId.trim().isEmpty ||
        refs.any((ref) => ref.refId.trim().isEmpty)) {
      throw StateError('Las referencias y el contexto local son obligatorios.');
    }
    return refs;
  }

  Future<_PreparedDraftItem> _prepareDraftItem(
    AgregarProductoBorradorCommand command,
    SaleProjection? sale, {
    bool preview = false,
  }) async {
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
    final priceEvent = variant.lastEventId ?? variant.createdEventId;
    if (priceEvent == null) {
      throw StateError('Falta trazabilidad de precio del artículo.');
    }
    if (command.expectedPriceConfigurationEventId != null &&
        command.expectedPriceConfigurationEventId != priceEvent) {
      throw StateError('El catálogo cambió durante la captura.');
    }
    await offerPricing?.requireCompatible();
    final price = EffectiveSalePrice.resolve(
      mode: sale?.pricingMode ?? 'normal',
      normal: variant.precioVentaMenor,
      offer: variant.offerPriceMinor,
    );
    final effective = price.amount;
    final atomic = preview
        ? (config is MeasuredSaleConfiguration ? 1 : null)
        : _readMeasuredQuantity(command, config, unit, effective);
    final snapshot = SaleItemSnapshot(
      variantId: variant.id,
      consumptionConfigurationKey: await products.consumptionConfigurationKey(
        variant.id,
      ),
      productName: product.nombre,
      variantName: variant.nombre,
      saleMode: config is MeasuredSaleConfiguration ? 'measured' : 'unit',
      quantity: atomic == null ? 1 : null,
      measuredQuantityAtomic: atomic,
      priceSnapshotVersion: 2,
      normalPriceMinorSnapshot: variant.precioVentaMenor,
      offerPriceMinorSnapshot: variant.offerPriceMinor,
      effectivePriceSource: price.source,
      priceSelection: 'inherit',
      priceConfigurationEventId: priceEvent,
      unitPriceMinor: effective,
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
    int unitPriceMinor,
  ) {
    if (config is MeasuredSaleConfiguration) {
      if ((command.measuredQuantity == null) ==
          (command.targetAmountMinor == null)) {
        throw const FormatException(
          'Ingresa una cantidad o un importe, solo uno.',
        );
      }
      final hasExpectedPrice =
          command.expectedUnitPriceMinor != null ||
          command.expectedPriceReferenceQuantityAtomic != null;
      if ((command.targetAmountMinor != null || hasExpectedPrice) &&
          (command.expectedUnitId == null ||
              command.expectedUnitId!.trim().isEmpty ||
              command.expectedUnitPriceMinor == null ||
              command.expectedPriceReferenceQuantityAtomic == null)) {
        throw const FormatException(
          'La captura requiere unidad, precio y referencia esperados.',
        );
      }
      if (unit == null ||
          !unit.activa ||
          command.expectedUnitId?.trim() != unit.id) {
        throw StateError(
          'La unidad de venta cambió o no está disponible. Vuelve a seleccionar el artículo.',
        );
      }
      if (hasExpectedPrice &&
          (command.expectedUnitPriceMinor != unitPriceMinor ||
              command.expectedPriceReferenceQuantityAtomic !=
                  config.priceReferenceQuantityAtomic)) {
        throw StateError(
          'El precio o su referencia cambió. Vuelve a seleccionar el artículo.',
        );
      }
      if (command.targetAmountMinor case final amount?) {
        return const MeasuredSaleCalculator().quantityAtomicForAmount(
          targetAmountMinor: amount,
          unitPriceMinor: unitPriceMinor,
          priceReferenceQuantityAtomic: config.priceReferenceQuantityAtomic,
        );
      }
      return const InventoryQuantityCodec().parsePositiveAtomic(
        command.measuredQuantity!,
        unit,
      );
    } else if (command.measuredQuantity != null ||
        command.targetAmountMinor != null ||
        command.expectedUnitId != null ||
        command.expectedUnitPriceMinor != null ||
        command.expectedPriceReferenceQuantityAtomic != null) {
      throw StateError(
        'El modo de venta cambió. Vuelve a seleccionar el artículo.',
      );
    }
    return null;
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
