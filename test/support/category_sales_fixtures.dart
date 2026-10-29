import 'package:pos_flutter/domain/articulos/articulo_listado.dart';
import 'package:pos_flutter/domain/articulos/variante_listado.dart';
import 'package:pos_flutter/domain/ventas/confirmed_sale.dart';
import 'package:pos_flutter/domain/ventas/sale_adjustment_document.dart';
import 'package:pos_flutter/domain/ventas/sale_adjustment_status.dart';
import 'package:pos_flutter/domain/ventas/sale_draft_item.dart';
import 'package:pos_flutter/presentation/pages/informes/models/report_period.dart';

final period = ReportPeriod.day(DateTime(2026, 10, 29));

ArticuloListado article({
  String? category = 'drinks',
  List<String> variants = const ['v'],
}) => ArticuloListado(
  productoId: 'p',
  nombre: 'Nombre actual',
  activo: true,
  categoriaId: category,
  categoriaNombre: category == null ? null : 'Bebidas',
  categoriaColor: null,
  variantesActivas: [
    for (final id in variants)
      VarianteListado(
        varianteId: id,
        nombre: null,
        precioVentaMenor: 999999,
        costoEstandarMenor: 999999,
        orden: 0,
      ),
  ],
);
SaleDraftItem line({
  String id = 'l',
  String variant = 'v',
  int? cost = 100,
  int total = 1000,
  int? quantity = 2,
}) => SaleDraftItem(
  id: id,
  variantId: variant,
  productName: 'Nombre histórico',
  variantName: null,
  quantity: quantity,
  measuredQuantityAtomic: quantity == null ? 500 : null,
  unitPriceMinor: 500,
  standardCostMinor: cost,
  priceReferenceQuantityAtomic: quantity == null ? 1000 : null,
  unitCode: quantity == null ? 'kg' : null,
  unitSymbol: quantity == null ? 'kg' : null,
  unitAtomicFactor: quantity == null ? 1000 : null,
  totalMinor: total,
);
ConfirmedSale sale({
  DateTime? date,
  List<SaleDraftItem>? lines,
  List<SaleAdjustmentDocument> adjustments = const [],
}) {
  final items = lines ?? [line()];
  return ConfirmedSale(
    id: 'ticket',
    createdAt: date ?? period.start,
    totalMinor: items.fold(0, (n, l) => n + l.totalMinor),
    receivedMinor: 0,
    changeMinor: 0,
    currency: 'MXN',
    deliveryStatus: 'not_required',
    reason: null,
    items: items,
    adjustments: adjustments,
  );
}

SaleAdjustmentDocument adjustment({
  String status = 'not_required',
  int? cost = 50,
}) => SaleAdjustmentDocument(
  operationId: status,
  eventId: status,
  saleId: 'ticket',
  businessDate: '2026-10-29',
  reason: 'Devolución',
  userId: 'u',
  deviceId: 'd',
  occurredAt: DateTime(2026, 10, 30),
  amountMinor: 250,
  method: 'cash',
  settlementAction: 'refund',
  deliveryStatus: status,
  officialStatus: SaleAdjustmentStatus.current,
  localStatus: SaleAdjustmentStatus.current,
  officialRevision: 0,
  localRevision: 0,
  lines: [
    (
      saleItemId: 'l',
      quantityAtomic: 1,
      amountMinor: 250,
      recoveredCostMinor: cost,
      destination: 'inventory',
    ),
  ],
  physicalEffectIds: [],
);
