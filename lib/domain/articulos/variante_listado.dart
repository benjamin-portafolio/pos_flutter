import '../inventario/recurso_inventario_listado.dart';

class VarianteListado {
  const VarianteListado({
    required this.varianteId,
    required this.nombre,
    required this.precioVentaMenor,
    this.costoEstandarMenor,
    this.offerPriceMinor,
    this.minimumStockAtomic,
    this.knowsMinimumStock = false,
    required this.orden,
    this.inventario,
    this.codigoBarras,
  });
  final String varianteId;

  /// Código textual para búsqueda; conserva ceros iniciales.
  final String? codigoBarras;
  final String? nombre;
  final int precioVentaMenor;
  final int? costoEstandarMenor;

  /// Oferta opcional, independiente del costo y del precio normal.
  final int? offerPriceMinor;

  /// Umbral atómico y conocimiento del contrato, independiente de SQL null.
  final int? minimumStockAtomic;
  final bool knowsMinimumStock;
  final int orden;

  /// Recurso y saldo de seguimiento directo; null si no controla existencias.
  final RecursoInventarioListado? inventario;
}
