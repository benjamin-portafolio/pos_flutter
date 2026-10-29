import 'package:flutter/material.dart';

/// Declaración de liquidación de una anulación, distinta de devolver mercancía.
class VoidSettlementForm extends StatelessWidget {
  const VoidSettlementForm({
    super.key,
    required this.action,
    required this.onChanged,
  });
  final String action;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: action,
    decoration: const InputDecoration(labelText: 'Liquidación del cobro'),
    items: const [
      DropdownMenuItem(
        value: 'refund_completed',
        child: Text('Dinero recibido y devuelto'),
      ),
      DropdownMenuItem(
        value: 'unreceived_correction',
        child: Text('Corregir cobro no recibido'),
      ),
    ],
    onChanged: onChanged == null ? null : (v) => onChanged!(v!),
  );
}
