import 'package:flutter/material.dart';

enum UnknownBarcodeAction { assign, create }

/// Opciones comunes de los lectores cuando el catálogo no resuelve el código.
class UnknownBarcodeDialog extends StatelessWidget {
  const UnknownBarcodeDialog({
    required this.code,
    this.forSale = false,
    super.key,
  });

  final String code;
  final bool forSale;

  void _close(BuildContext context, [UnknownBarcodeAction? action]) {
    if (ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop(action);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Código no encontrado'),
    content: Text(
      'No se encontró un artículo con este código: $code.'
      '${forSale ? ' Puedes asignarlo a una variante existente o crear un artículo para agregarlo a la venta.' : ''}',
    ),
    actions: [
      TextButton(
        onPressed: () => _close(context),
        child: const Text('Cancelar'),
      ),
      TextButton(
        onPressed: () => _close(context, UnknownBarcodeAction.create),
        child: const Text('Dar de alta un producto'),
      ),
      FilledButton(
        onPressed: () => _close(context, UnknownBarcodeAction.assign),
        child: const Text('Asignar a una variante existente'),
      ),
    ],
  );
}
