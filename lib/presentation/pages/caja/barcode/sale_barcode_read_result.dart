import '../../../../domain/articulos/variante_por_codigo_barras.dart';
import '../../articulos/sale_quantity_form_result.dart';
import 'sale_barcode_read_outcome.dart';

/// Datos de presentación; `added` se entrega solo tras confirmar el comando.
class SaleBarcodeReadResult {
  const SaleBarcodeReadResult({
    required this.code,
    required this.outcome,
    this.candidate,
    this.quantity,
  });

  final String code;
  final SaleBarcodeReadOutcome outcome;
  final VariantePorCodigoBarras? candidate;
  final SaleQuantityFormResult? quantity;

  /// Cantidad física revisada para mensajes, cualquiera que sea la fuente.
  String? get measuredQuantity =>
      quantity?.measuredQuantity ?? quantity?.displayQuantity;
}
