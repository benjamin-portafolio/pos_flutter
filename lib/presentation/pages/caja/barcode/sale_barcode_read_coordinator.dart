import '../../../../application/commands/ventas/agregar_producto_borrador_command.dart';
import '../../../../application/commands/ventas/venta_borrador_command_service.dart';
import '../../../../domain/articulos/sale_configuration.dart';
import '../../../../domain/articulos/variante_por_codigo_barras.dart';
import '../../../../domain/repositories/producto_repository.dart';
import '../../../../domain/ventas/measured_sale_conditions.dart';
import '../../articulos/sale_quantity_form_result.dart';
import 'sale_barcode_assigned_exception.dart';
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

  Future<MeasuredSaleConditions?> conditionsFor(String variantId) =>
      _products.obtenerCondicionesVentaMedida(variantId);

  Future<SaleBarcodeReadResult> read(
    String code, {
    required bool Function() canContinue,
    required Future<VariantePorCodigoBarras?> Function(
      List<VariantePorCodigoBarras> candidates,
    )
    selectProduct,
    required Future<SaleQuantityFormResult?> Function(
      VariantePorCodigoBarras candidate,
    )
    requestQuantity,
    Future<VariantePorCodigoBarras?> Function(String code)? assignUnknownCode,
    Future<void> Function()? waitUntilReady,
    void Function()? onSaving,
    void Function()? onCommandStarted,
  }) async {
    var barcodeAssigned = false;
    SaleBarcodeReadResult result(
      SaleBarcodeReadOutcome outcome, {
      VariantePorCodigoBarras? candidate,
      SaleQuantityFormResult? quantity,
    }) => SaleBarcodeReadResult(
      code: code,
      outcome: outcome,
      candidate: candidate,
      quantity: quantity,
      barcodeAssigned: barcodeAssigned,
    );

    try {
      if (!canContinue()) return result(SaleBarcodeReadOutcome.interrupted);
      final candidates = await _products.buscarVariantesPorCodigoBarras(code);
      await waitUntilReady?.call();
      if (!canContinue()) return result(SaleBarcodeReadOutcome.interrupted);
      if (candidates.isEmpty && assignUnknownCode == null) {
        return result(SaleBarcodeReadOutcome.notFound);
      }

      final candidate = candidates.isEmpty
          ? await assignUnknownCode!(code)
          : candidates.length == 1
          ? candidates.single
          : await selectProduct(candidates);
      barcodeAssigned = candidates.isEmpty && candidate != null;
      await waitUntilReady?.call();
      if (!canContinue()) return result(SaleBarcodeReadOutcome.interrupted);
      if (candidate == null) {
        return result(SaleBarcodeReadOutcome.selectionCancelled);
      }

      SaleQuantityFormResult? quantity;
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
      onCommandStarted?.call();
      await _commands.agregar(
        quantity?.toCommand(candidate.varianteId) ??
            AgregarProductoBorradorCommand(variantId: candidate.varianteId),
      );
      return result(
        SaleBarcodeReadOutcome.added,
        candidate: candidate,
        quantity: quantity,
      );
    } catch (error, stack) {
      if (barcodeAssigned) {
        Error.throwWithStackTrace(SaleBarcodeAssignedException(error), stack);
      }
      rethrow;
    }
  }
}
