import 'report_money.dart';

/// Métodos de pago reconocidos por el desglose de ventas.
///
/// Cualquier método distinto a estos se agrupa en una categoría propia
/// "Otros métodos"; nunca se atribuye silenciosamente a efectivo.
enum MetodoVenta { efectivo, transferencia, credito, otros }

extension MetodoVentaInfo on MetodoVenta {
  bool get esCredito => this == MetodoVenta.credito;

  /// Condición de coincidencia contra `ConfirmedSale.paymentMethod`.
  bool matches(String paymentMethod) => switch (this) {
    MetodoVenta.efectivo => paymentMethod == 'cash',
    MetodoVenta.transferencia => paymentMethod == 'transfer',
    MetodoVenta.credito => paymentMethod == 'credit',
    MetodoVenta.otros =>
      paymentMethod != 'cash' &&
          paymentMethod != 'transfer' &&
          paymentMethod != 'credit',
  };
}

/// Categoría de ventas por método dentro del período, con su importe en
/// `totalMinor` (no `receivedMinor`), porcentaje del total y número de ventas.
class VentasPorMetodoCategoria {
  const VentasPorMetodoCategoria({
    required this.metodo,
    required this.amountMinor,
    required this.ventasCount,
  });

  final MetodoVenta metodo;
  final BigInt amountMinor;
  final int ventasCount;

  String get label => switch (metodo) {
    MetodoVenta.efectivo => 'Efectivo',
    MetodoVenta.transferencia => 'Transferencia',
    MetodoVenta.credito => 'Crédito',
    MetodoVenta.otros => 'Otros métodos',
  };

  double percentOf(BigInt total) => ReportMoney.percentOf(amountMinor, total);
}

/// Desglose de ventas confirmadas del período por `paymentMethod`.
class VentasPorMetodoReport {
  const VentasPorMetodoReport({
    required this.categorias,
    required this.totalMinor,
    required this.salesCount,
  });

  final List<VentasPorMetodoCategoria> categorias;

  /// Suma exacta de `totalMinor` de todas las ventas confirmadas del período;
  /// coincide con la tarjeta "Ventas totales".
  final BigInt totalMinor;

  /// Ventas confirmadas del período.
  final int salesCount;

  VentasPorMetodoCategoria? categoria(MetodoVenta metodo) {
    for (final category in categorias) {
      if (category.metodo == metodo) return category;
    }
    return null;
  }

  /// Importe y etiqueta del total general para el encabezado de la pantalla.
  String get montoTotal => ReportMoney.money(totalMinor);
}