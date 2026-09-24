import 'report_money.dart';

/// Estado de cálculo del beneficio bruto según la disponibilidad de costos.
enum BeneficioBrutoEstado {
  /// Todas las líneas del período tienen costo conocido (incluye costo cero).
  total,

  /// Hay líneas con costo conocido y líneas sin costo.
  parcial,

  /// Ninguna línea del período tiene costo conocido.
  noDisponible,
}

/// Resultado del beneficio bruto de un período, calculado solo con el costo
/// estándar capturado en cada venta. No consulta el catálogo actual.
class BeneficioBrutoReport {
  const BeneficioBrutoReport({
    required this.estado,
    required this.profitMinor,
    required this.ventasCount,
    required this.lineasConCosto,
    required this.lineasSinCosto,
    required this.vendidoSinCostoMinor,
  });

  final BeneficioBrutoEstado estado;
  final BigInt profitMinor;

  /// Ventas confirmadas del período que aportan líneas al cálculo.
  final int ventasCount;

  /// Líneas del período con costo conocido (incluye costo cero).
  final int lineasConCosto;

  /// Líneas del período cuyo costo se desconoce (`null`).
  final int lineasSinCosto;

  /// Importe vendido (totalMinor) acumulado de las líneas sin costo.
  final BigInt vendidoSinCostoMinor;

  /// Título de la tarjeta según la disponibilidad de costos.
  String get titulo => switch (estado) {
    BeneficioBrutoEstado.total => 'BENEFICIO BRUTO TOTAL',
    BeneficioBrutoEstado.parcial => 'BENEFICIO BRUTO PARCIAL',
    BeneficioBrutoEstado.noDisponible => 'NO DISPONIBLE',
  };

  /// Importe mostrado con signo, o `null` cuando el estado es no disponible.
  String? get monto {
    if (estado == BeneficioBrutoEstado.noDisponible) return null;
    return ReportMoney.signedMoney(profitMinor);
  }

  /// Detalle complementario que aclara líneas sin costo (solo parcial).
  String? get detalleSinCosto {
    if (estado != BeneficioBrutoEstado.parcial) return null;
    return 'Sin costo: ${ReportMoney.money(vendidoSinCostoMinor)} · '
        '$lineasSinCosto ${lineasSinCosto == 1 ? 'línea' : 'líneas'}';
  }
}