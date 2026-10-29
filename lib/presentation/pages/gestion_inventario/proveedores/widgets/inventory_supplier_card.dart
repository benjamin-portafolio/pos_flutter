import 'package:flutter/material.dart';
import '../../../../../domain/proveedores/proveedor.dart';
import '../../widgets/inventory_margin_label.dart';

class InventorySupplierCard extends StatelessWidget {
  const InventorySupplierCard({
    required this.proveedor,
    required this.onOpen,
    this.margenPromedioPorcentaje,
    this.margenCargando = false,
    this.margenError = false,
    super.key,
  });
  final Proveedor proveedor;
  final VoidCallback onOpen;
  final double? margenPromedioPorcentaje;
  final bool margenCargando;
  final bool margenError;

  @override
  Widget build(BuildContext context) {
    final details = [
      proveedor.telefono,
      proveedor.notas,
    ].whereType<String>().join('\n');

    return Card(
      child: ListTile(
        key: Key('supplier_${proveedor.id}'),
        leading: const Icon(Icons.local_shipping_outlined),
        title: Text(proveedor.nombre),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (details.isNotEmpty)
              Text(details, maxLines: 3, overflow: TextOverflow.ellipsis),
            if (details.isNotEmpty) const SizedBox(height: 4),
            InventoryMarginLabel(
              porcentaje: margenPromedioPorcentaje,
              loading: margenCargando,
              hasError: margenError,
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onOpen,
      ),
    );
  }
}
