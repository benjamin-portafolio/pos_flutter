import '../../../../domain/ventas/confirmed_sale.dart';
import '../../../../domain/ventas/sale_draft_item.dart';
import 'beneficio_bruto_report.dart';
import 'report_period.dart';
import 'ventas_por_metodo_report.dart';

/// Cálculos centralizados de los informes de ventas, fuera de los widgets.
///
/// Todas las operaciones monetarias usan enteros en centavos y `BigInt` para
/// acumular sin pérdida de precisión. Los reportes leen únicamente datos
/// locales ya persistidos (el snapshot de la venta), sin consultar el catálogo
/// actual ni generar eventos.
class SalesReportsCalculator {
  const SalesReportsCalculator._();

  /// Ventas confirmadas cuya fecha cae dentro del período, con ambos días
  /// incluidos según `ReportPeriod.contains`. Fuente única de verdad para la
  /// tarjeta de ventas totales, el beneficio bruto y el desglose por método.
  static List<ConfirmedSale> salesInPeriod(
    ReportPeriod period,
    Iterable<ConfirmedSale> sales,
  ) => sales.where((sale) => period.contains(sale.createdAt)).toList();

  /// Importe de "Ventas totales": suma de `totalMinor` del período.
  static BigInt ventasTotales(
    ReportPeriod period,
    Iterable<ConfirmedSale> sales,
  ) => salesInPeriod(
    period,
    sales,
  ).fold(BigInt.zero, (sum, sale) => sum + BigInt.from(sale.totalMinor));

  /// Beneficio bruto del período sobre el costo histórico de cada línea.
  ///
  /// - unit: costo de línea = costo estándar × cantidad.
  /// - measured: costo de línea = costo × cantidad atómica vendida,
  ///   redondeado half-up sobre la cantidad atómica de referencia.
  /// - Beneficio de línea = `totalMinor` − costo de línea.
  /// - Solo participan las líneas con costo conocido (`null` = desconocido);
  ///   el costo cero es un valor conocido válido.
  static BeneficioBrutoReport grossProfit(
    ReportPeriod period,
    Iterable<ConfirmedSale> sales,
  ) {
    final inPeriod = salesInPeriod(period, sales);
    var profit = BigInt.zero;
    var lineasConCosto = 0;
    var lineasSinCosto = 0;
    var vendidoSinCosto = BigInt.zero;
    for (final sale in inPeriod) {
      for (final line in sale.items) {
        final cost = line.standardCostMinor;
        if (cost == null) {
          lineasSinCosto++;
          vendidoSinCosto += BigInt.from(line.totalMinor);
          continue;
        }
        lineasConCosto++;
        profit += BigInt.from(line.totalMinor) - lineCost(line, cost);
      }
    }
    final estado = lineasSinCosto == 0
        ? BeneficioBrutoEstado.total
        : lineasConCosto == 0
        ? BeneficioBrutoEstado.noDisponible
        : BeneficioBrutoEstado.parcial;
    return BeneficioBrutoReport(
      estado: estado,
      profitMinor: profit,
      ventasCount: inPeriod.length,
      lineasConCosto: lineasConCosto,
      lineasSinCosto: lineasSinCosto,
      vendidoSinCostoMinor: vendidoSinCosto,
    );
  }

  /// Costo total de una línea con costo conocido, en centavos.
  ///
  /// Reutiliza la misma base cuantitativa y regla de redondeo half-up del
  /// precio de la línea (ver `SaleItemSnapshot.totalMinor`).
  static BigInt lineCost(SaleDraftItem line, int standardCostMinor) {
    final cost = BigInt.from(standardCostMinor);
    final quantity = line.quantity;
    if (quantity != null) return cost * BigInt.from(quantity);
    final atomic = BigInt.from(line.measuredQuantityAtomic!);
    final reference = BigInt.from(line.priceReferenceQuantityAtomic!);
    return (cost * atomic * BigInt.two + reference) ~/ (reference * BigInt.two);
  }

  /// Ventas confirmadas del período agrupadas por `paymentMethod`, sumando
  /// `totalMinor`. No usa `receivedMinor`, ni abonos, anticipos o
  /// aplicaciones de crédito: solo las ventas confirmadas del período.
  static VentasPorMetodoReport ventasPorMetodo(
    ReportPeriod period,
    Iterable<ConfirmedSale> sales,
  ) {
    final inPeriod = salesInPeriod(period, sales);
    final amounts = <MetodoVenta, BigInt>{};
    final counts = <MetodoVenta, int>{};
    for (final sale in inPeriod) {
      final metodo = _metodo(sale.paymentMethod);
      amounts.update(
        metodo,
        (value) => value + BigInt.from(sale.totalMinor),
        ifAbsent: () => BigInt.from(sale.totalMinor),
      );
      counts.update(metodo, (value) => value + 1, ifAbsent: () => 1);
    }
    final orden = [
      MetodoVenta.efectivo,
      MetodoVenta.transferencia,
      MetodoVenta.credito,
      MetodoVenta.otros,
    ];
    final categorias = [
      for (final metodo in orden)
        if (metodo != MetodoVenta.otros || counts[metodo] != null)
          VentasPorMetodoCategoria(
            metodo: metodo,
            amountMinor: amounts[metodo] ?? BigInt.zero,
            ventasCount: counts[metodo] ?? 0,
          ),
    ];
    return VentasPorMetodoReport(
      categorias: categorias,
      totalMinor: categorias.fold(
        BigInt.zero,
        (sum, category) => sum + category.amountMinor,
      ),
      salesCount: inPeriod.length,
    );
  }

  static MetodoVenta _metodo(String paymentMethod) => switch (paymentMethod) {
    'cash' => MetodoVenta.efectivo,
    'transfer' => MetodoVenta.transferencia,
    'credit' => MetodoVenta.credito,
    _ => MetodoVenta.otros,
  };
}