import 'package:flutter/material.dart';

/// Tarjeta base de los formularios de recursos de inventario. La comparten el
/// formulario del recurso y su sección de movimientos.
class InventoryFormCard extends StatelessWidget {
  const InventoryFormCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: child,
      ),
    );
  }
}
