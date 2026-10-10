import '../../../../application/commands/ventas/agregar_producto_borrador_command.dart';
import '../../../../application/commands/ventas/venta_borrador_command_service.dart';
import '../../../../domain/articulos/sale_configuration.dart';
import '../../../../domain/articulos/variante_por_codigo_barras.dart';
import '../../../../domain/repositories/producto_repository.dart';
import 'sale_barcode_read_outcome.dart';
import 'sale_barcode_read_result.dart';

/// Resuelve un código ya validado y agrega sobre el borrador persistido.
/// Los callbacks presentan selección/cantidad y protegen la vigencia de la
/// intención. Cámara, teclado, admisión y mensajes pertenecen a cada lector.
class SaleBarcodeReadCoordinator {
  const SaleBarcodeReadCoordinator({
    required ProductoRepository products,
    required VentaBorradorCommandService commands,
  }) : _products = products,
       _commands = commands;

  final ProductoRepository _products;
  final VentaBorradorCommandService _commands;

  Future<SaleBarcodeReadResult> read(
    String code, {
    required bool Function() canContinue,
    required Future<VariantePorCodigoBarras?> Function(
      List<VariantePorCodigoBarras> candidates,
    )
    selectProduct,
    required Future<String?> Function(VariantePorCodigoBarras candidate)
    requestQuantity,
    Future<void> Function()? waitUntilReady,
    void Function()? onSaving,
  }) async {
    SaleBarcodeReadResult result(
      SaleBarcodeReadOutcome outcome, {
      VariantePorCodigoBarras? candidate,
      String? quantity,
    }) => SaleBarcodeReadResult(
      code: code,
      outcome: outcome,
      candidate: candidate,
      measuredQuantity: quantity,
    );

    if (!canContinue()) return result(SaleBarcodeReadOutcome.interrupted);
    final candidates = await _products.buscarVariantesPorCodigoBarras(code);
    await waitUntilReady?.call();
    if (!canContinue()) return result(SaleBarcodeReadOutcome.interrupted);
    if (candidates.isEmpty) return result(SaleBarcodeReadOutcome.notFound);

    final candidate = candidates.length == 1
        ? candidates.single
        : await selectProduct(candidates);
    await waitUntilReady?.call();
    if (!canContinue()) return result(SaleBarcodeReadOutcome.interrupted);
    if (candidate == null) {
      return result(SaleBarcodeReadOutcome.selectionCancelled);
    }

    String? quantity;
    final unit = candidate.unidadVenta;
    if (candidate.saleConfiguration is MeasuredSaleConfiguration) {
      if (unit == null || !unit.activa) {
        return result(
          SaleBarcodeReadOutcome.unitUnavailable,
          candidate: candidate,
        );
      }
      quantity = await requestQuantity(candidate);
      await waitUntilReady?.call();
      if (!canContinue()) return result(SaleBarcodeReadOutcome.interrupted);
      if (quantity == null) {
        return result(
          SaleBarcodeReadOutcome.quantityCancelled,
          candidate: candidate,
        );
      }
    }

    onSaving?.call();
    await waitUntilReady?.call();
    // Comprobar después del callback y de la pausa: ninguno puede iniciar un
    // comando de una sesión que terminó mientras esperaba. Una vez llamado,
    // el command service completa su operación atómica sin rollback de UI.
    if (!canContinue()) return result(SaleBarcodeReadOutcome.interrupted);
    await _commands.agregar(
      AgregarProductoBorradorCommand(
        variantId: candidate.varianteId,
        measuredQuantity: quantity,
        expectedUnitId: unit?.id,
      ),
    );
    return result(
      SaleBarcodeReadOutcome.added,
      candidate: candidate,
      quantity: quantity,
    );
  }
}
