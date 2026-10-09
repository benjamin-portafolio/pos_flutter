import 'package:flutter/material.dart';
import '../../../../../domain/proveedores/proveedor.dart';

class InventorySupplierCard extends StatelessWidget {
  const InventorySupplierCard({
    required this.proveedor,
    required this.onOpen,
    super.key,
  });
  final Proveedor proveedor;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      key: Key('supplier_${proveedor.id}'),
      leading: const Icon(Icons.local_shipping_outlined),
      title: Text(proveedor.nombre),
      subtitle: proveedor.telefono == null && proveedor.notas == null
          ? null
          : Text(
              [
                proveedor.telefono,
                proveedor.notas,
              ].whereType<String>().join('\n'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onOpen,
    ),
  );
}
