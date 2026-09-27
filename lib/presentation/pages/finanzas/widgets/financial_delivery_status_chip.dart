import 'package:flutter/material.dart';

/// Chip visual del estado de entrega de un registro financiero adicional
/// (contrato §8.3). Una incidencia de entrega (`rejected`/`conflict`) no oculta
/// ni revierte el dinero ya registrado: solo informa que el servidor aún no lo
/// aceptó y el motivo se muestra en el detalle.
class FinancialDeliveryStatusChip extends StatelessWidget {
  const FinancialDeliveryStatusChip({
    super.key,
    required this.status,
    this.rejectionReason,
  });

  /// `delivery_status` del evento: `not_required` | `pending` | `delivered` |
  /// `rejected` | `conflict`.
  final String status;
  final String? rejectionReason;

  String get _label => _labelFor(status);

  static String _labelFor(String status) => switch (status) {
    'not_required' => 'Registro local',
    'pending' => 'Pendiente de sincronizar',
    'delivered' => 'Sincronizada',
    'rejected' || 'conflict' => 'Requiere atención',
    _ => 'Estado desconocido',
  };

  static Color _colorFor(String status) => switch (status) {
    'delivered' => Colors.green,
    'not_required' => Colors.blueGrey,
    'pending' => Colors.orange,
    'rejected' || 'conflict' => Colors.red,
    _ => Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    if (status == 'delivered' || status == 'not_required') {
      return Chip(
        visualDensity: VisualDensity.compact,
        label: Text(_label),
        labelStyle: TextStyle(
          fontSize: 12,
          color: _colorFor(status),
        ),
        side: BorderSide(color: _colorFor(status).withValues(alpha: 0.6)),
        backgroundColor: _colorFor(status).withValues(alpha: 0.08),
      );
    }
    final color = _colorFor(status);
    final motivo = rejectionReason ?? 'Consultar el servidor.';
    return Tooltip(
      message: motivo,
      child: Chip(
        visualDensity: VisualDensity.compact,
        avatar: const Icon(Icons.error_outline, size: 16),
        label: Text(_label),
        labelStyle: TextStyle(fontSize: 12, color: color),
        side: BorderSide(color: color.withValues(alpha: 0.6)),
        backgroundColor: color.withValues(alpha: 0.08),
      ),
    );
  }
}