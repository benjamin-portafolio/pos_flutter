import '../../sync/projections/cliente_projection_store.dart';
import 'package:uuid/uuid.dart';
import '../../../domain/articulos/sale_configuration.dart';
import '../../../domain/ventas/sale_status.dart';
import '../../sync/local_event_store.dart';
import '../../sync/models/sync_event.dart';
import '../../sync/payloads/confirmed_sale_line.dart';
import '../../sync/payloads/sale_consumption.dart';
import '../../sync/payloads/venta_confirmada_payload.dart';
import '../../sync/projections/sale_draft_projection_store.dart';
import '../../sync/projections/producto_projection_store.dart';
import '../../sync/projections/inventory_projection_store.dart';
import '../local_command_context.dart';
import 'confirmar_venta_command.dart';

class VentaCommandService {
  VentaCommandService({
    required this.drafts,
    required this.products,
    required this.inventory,
    required this.events,
    required this.context,
    this.clientes,
  });
  final SaleDraftProjectionStore drafts;
  final ProductoProjectionStore products;
  final InventoryProjectionStore inventory;
  final LocalEventStore events;
  final LocalCommandContext context;
  final ClienteProjectionStore? clientes;
  final _uuid = const Uuid();

  Future<String> confirmar(
    ConfirmarVentaCommand command,
  ) => drafts.atomic(() async {
    final sale = await drafts.findById(command.saleId);
    if (sale == null ||
        !sale.active ||
        sale.status != SaleStatus.borrador ||
        sale.userId != context.userId ||
        sale.deviceId != context.deviceId ||
        sale.lastEventId != command.expectedDraftEventId ||
        sale.totalMinor != command.expectedTotalMinor) {
      throw StateError(
        'El borrador cambió o ya fue cobrado. Revísalo antes de cobrar.',
      );
    }
    final cliente = command.clienteId == null
        ? null
        : await clientes?.findById(command.clienteId!);
    if ((command.clienteId != null &&
            (cliente == null ||
                !cliente.active ||
                cliente.createdEventId == null)) ||
        (command.paymentMethod == 'credit' && cliente == null)) {
      throw StateError('Selecciona un cliente activo para la venta.');
    }
    final lines = <ConfirmedSaleLine>[];
    final dependencies = <String>{
      if (cliente?.createdEventId != null) cliente!.createdEventId!,
    };
    for (final item in await drafts.items(sale.id)) {
      if (!item.active) continue;
      final variant = await products.findVariantById(item.snapshot.variantId);
      final product = variant == null
          ? null
          : await products.findProductById(variant.productoId);
      if (variant == null ||
          !variant.active ||
          product == null ||
          !product.active) {
        throw StateError(
          'Un artículo ya no está disponible. Revisa el borrador; se conserva sin cobrar.',
        );
      }
      if (item.snapshot.consumptionConfigurationKey != null &&
          item.snapshot.consumptionConfigurationKey !=
              await products.consumptionConfigurationKey(variant.id)) {
        throw StateError(
          'El consumo del artículo cambió. Revisa y vuelve a capturar el borrador antes de cobrar.',
        );
      }
      final state = await products.snapshot(product.id);
      final config = state.saleConfiguration;
      final unit = config is MeasuredSaleConfiguration
          ? await inventory.findUnitById(config.saleUnitId)
          : null;
      if ((config is MeasuredSaleConfiguration) !=
              (item.snapshot.saleMode == 'measured') ||
          config.priceReferenceQuantityAtomic !=
              item.snapshot.priceReferenceQuantityAtomic ||
          (unit != null &&
              (!unit.active ||
                  unit.atomicFactor != item.snapshot.unitAtomicFactor))) {
        throw StateError(
          'La configuración del artículo cambió. Revisa el borrador.',
        );
      }
      final v = state.variantes.singleWhere((v) => v.id == variant.id);
      final mode = v.inventoryItemId != null
          ? 'direct'
          : v.componentesReceta.isNotEmpty
          ? 'recipe'
          : 'none';
      final components = <String, int>{
        if (v.inventoryItemId != null) v.inventoryItemId!: 1,
        for (final c in v.componentesReceta)
          c.inventoryItemId: c.quantityAtomic,
      };
      final consumption = <SaleConsumption>[];
      for (final entry in components.entries) {
        final resource = await inventory.findItemById(entry.key);
        if (resource == null || !resource.active) {
          throw StateError(
            'Un recurso ya no está disponible. Revisa el borrador.',
          );
        }
        if (resource.createdEventId != null) {
          dependencies.add(resource.createdEventId!);
        }
        final delta = -SaleConsumption.rounded(
          entry.value,
          item.snapshot.quantity ?? item.snapshot.measuredQuantityAtomic!,
          mode == 'recipe'
              ? item.snapshot.priceReferenceQuantityAtomic ?? 1
              : 1,
        );
        consumption.add(
          SaleConsumption(
            inventoryItemId: entry.key,
            componentAtomic: entry.value,
            deltaAtomic: delta,
            movementId: delta == 0 ? null : _uuid.v4(),
          ),
        );
      }
      final configEvent = variant.lastEventId ?? variant.createdEventId;
      if (configEvent == null) {
        throw StateError('Falta trazabilidad del artículo.');
      }
      dependencies.add(configEvent);
      lines.add(
        ConfirmedSaleLine(
          id: item.id,
          productId: product.id,
          configurationEventId: configEvent,
          snapshot: item.snapshot,
          consumptionMode: mode,
          saleUnitId: config is MeasuredSaleConfiguration
              ? config.saleUnitId
              : null,
          consumptions: consumption,
        ),
      );
    }
    final credit = command.paymentMethod == 'credit';
    if (credit && command.receivedMinor != null && command.receivedMinor != 0) {
      throw const FormatException('Una venta a crédito no recibe efectivo.');
    }
    final received = credit ? 0 : command.receivedMinor ?? sale.totalMinor;
    final payload = VentaConfirmadaPayload(
      paymentId: credit ? null : _uuid.v4(),
      paymentMethod: command.paymentMethod,
      occurredAtMs: credit ? DateTime.now().millisecondsSinceEpoch : null,
      clienteId: cliente?.id,
      clienteEventId: cliente?.createdEventId,
      clienteNombre: cliente?.nombre,
      totalMinor: sale.totalMinor,
      receivedMinor: received,
      changeMinor: credit ? 0 : received - sale.totalMinor,
      currency: 'MXN',
      lines: lines,
      dependencyEventIds: dependencies.toList(),
    );
    final refs = payload.refs(sale.id);
    if (context.userId.trim().isEmpty ||
        context.deviceId.trim().isEmpty ||
        refs.any((r) => r.refId.trim().isEmpty)) {
      throw StateError('Contexto o referencias inválidos.');
    }
    final eventId = _uuid.v4();
    await events.appendAndApply(
      SyncEvent(
        eventId: eventId,
        aggregateType: VentaConfirmadaPayload.aggregateType,
        aggregateId: sale.id,
        eventType: VentaConfirmadaPayload.eventType,
        deviceId: context.deviceId,
        userId: context.userId,
        createdAtLocal: DateTime.now(),
        baseVersion: 1,
        payload: payload.toJson(),
      ),
      refs: refs,
    );
    return eventId;
  });
}
