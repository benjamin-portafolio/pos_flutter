import '../sync/payloads/supplier_replenishment_patch.dart';
import '../edicion_masiva/cambio_explicito.dart';

/// Cambios de catálogo y seguimiento de una variante identificada.
class ArticuloImportVarianteCambio {
  const ArticuloImportVarianteCambio({
    required this.id,
    required this.linea,
    this.replenishment = const SupplierReplenishmentPatch.preserve(),
    this.targetUnitId,
    this.offerPrice = const CambioExplicito.conservar(),
    required this.precioVentaMinor,
    this.nombre,
    this.precioCosteMinor,
    this.codigoBarras,
    this.seguimiento,
    this.recursoInventarioId,
  });
  final String id;
  final int linea;
  final String? nombre;
  final int precioVentaMinor;
  final SupplierReplenishmentPatch replenishment;
  final String? targetUnitId;
  final CambioExplicito<int?> offerPrice;
  final int? precioCosteMinor;
  final String? codigoBarras;
  final bool? seguimiento;
  final String? recursoInventarioId;
}
