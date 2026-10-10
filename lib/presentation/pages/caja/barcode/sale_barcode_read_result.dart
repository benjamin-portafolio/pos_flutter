import '../../../../domain/articulos/variante_por_codigo_barras.dart';
import 'sale_barcode_read_outcome.dart';

/// Datos de presentación; `added` se entrega solo tras confirmar el comando.
class SaleBarcodeReadResult {
  const SaleBarcodeReadResult({
    required this.code,
    required this.outcome,
    this.candidate,
    this.measuredQuantity,
  });

  final String code;
  final SaleBarcodeReadOutcome outcome;
  final VariantePorCodigoBarras? candidate;
  final String? measuredQuantity;
}
