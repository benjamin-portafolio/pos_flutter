import 'package:flutter/material.dart';
import '../../../application/commands/ventas/prepare_sale_adjustment.dart';
import '../../../application/commands/ventas/sale_adjustment_command_service.dart';
import '../../../application/sync/projections/cash_projection_store.dart';
import '../../../core/di/injection.dart';
import '../../../domain/repositories/sale_adjustment_repository.dart';
import '../../../domain/ventas/adjusted_sale.dart';
import '../../../domain/ventas/sale_adjustment_status.dart';
import 'sale_adjustment_form_screen.dart';
import 'sale_adjustment_receipt_screen.dart';

class SaleAdjustmentActions extends StatelessWidget {
  const SaleAdjustmentActions({
    super.key,
    required this.sale,
    required this.repository,
  });
  final AdjustedSale sale;
  final SaleAdjustmentRepository repository;
  static String status(AdjustedSale sale) => switch (sale.status) {
    SaleAdjustmentStatus.current => 'Vigente',
    SaleAdjustmentStatus.voided => 'Anulada',
    SaleAdjustmentStatus.partiallyReturned => 'Devolución parcial',
    SaleAdjustmentStatus.fullyReturned => 'Devolución total',
  };
  Future<void> _open(BuildContext context, bool voidSale) async {
    final commands = getIt<SaleAdjustmentCommandService>();
    try {
      await commands.ensureAvailable(refresh: true);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
      return;
    }
    if (!context.mounted) return;
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => SaleAdjustmentFormScreen(
          sale: sale,
          voidSale: voidSale,
          prepare: PrepareSaleAdjustment(
            commands,
            getIt<CashProjectionStore>(),
          ),
        ),
      ),
    );
    if (context.mounted && id != null) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => SaleAdjustmentReceiptScreen(
            operationId: id,
            repository: repository,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<bool>(
    tooltip: 'Acciones de venta',
    onSelected: (v) => _open(context, v),
    itemBuilder: (_) => [
      PopupMenuItem(
        value: true,
        enabled:
            !sale.hasIncident && sale.status == SaleAdjustmentStatus.current,
        child: const Text('Anular por error'),
      ),
      PopupMenuItem(
        value: false,
        enabled:
            !sale.hasIncident &&
            [
              SaleAdjustmentStatus.current,
              SaleAdjustmentStatus.partiallyReturned,
            ].contains(sale.status),
        child: const Text('Registrar devolución'),
      ),
    ],
  );
}
