import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../application/commands/ventas/sale_reconciliation_command_service.dart';
import '../../../application/sync/projections/sale_adjustment_store.dart';
import '../../../application/sync/projections/cash_projection_store.dart';
import 'sale_incident_screen.dart';

class SaleIncidentAction extends StatelessWidget {
  const SaleIncidentAction({super.key, required this.incidentId});
  final String incidentId;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: const Icon(Icons.warning_amber),
    label: const Text('Ver incidencia y conciliación'),
    onPressed: !getIt.isRegistered<SaleReconciliationCommandService>()
        ? null
        : () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => SaleIncidentScreen(
                incidentId: incidentId,
                commands: getIt<SaleReconciliationCommandService>(),
                adjustments: getIt<SaleAdjustmentStore>(),
                cash: getIt<CashProjectionStore>(),
              ),
            ),
          ),
  );
}
