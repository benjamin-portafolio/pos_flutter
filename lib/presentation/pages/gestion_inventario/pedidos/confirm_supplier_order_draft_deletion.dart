import 'package:flutter/material.dart';

Future<bool> confirmSupplierOrderDraftDeletion(
  BuildContext context,
  String supplierName,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar borrador'),
        content: Text(
          '¿Eliminar el borrador de $supplierName?\n'
          'Se quitará de Borradores y se conservará como cancelado en Historial. '
          'No cambia las existencias.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar borrador'),
          ),
        ],
      ),
    ) ??
    false;
