import 'package:flutter/material.dart';
import '../../../../../domain/articulos/proveedor_variante.dart';
import '../../../../../domain/proveedores/proveedor.dart';
import '../../../../../domain/repositories/proveedor_repository.dart';

/// La selección es explícita y solo ofrece relaciones cotizadas del borrador.
class CurrentSupplierSelector extends StatelessWidget {
  const CurrentSupplierSelector({
    required this.value,
    required this.relations,
    required this.onChanged,
    this.repository,
    super.key,
  });
  final String? value;
  final List<ProveedorVariante>? relations;
  final ProveedorRepository? repository;
  final ValueChanged<String?>? onChanged;
  @override
  Widget build(BuildContext context) => StreamBuilder<List<Proveedor>>(
    stream: repository?.watchProveedores(),
    builder: (context, snapshot) {
      final names = {
        for (final p in snapshot.data ?? <Proveedor>[]) p.id: p.nombre,
      };
      return DropdownButtonFormField<String>(
        key: const Key('variant_current_supplier_field'),
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Proveedor actual',
          helperText: 'Solo proveedores asociados. Sin selección automática.',
        ),
        items: [
          const DropdownMenuItem<String>(
            value: null,
            child: Text('Sin proveedor actual'),
          ),
          for (final p in relations ?? <ProveedorVariante>[])
            DropdownMenuItem(
              value: p.proveedorId,
              child: Text(
                names[p.proveedorId] == null
                    ? p.proveedorId
                    : '${names[p.proveedorId]} · ${p.proveedorId.substring(0, 8)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: onChanged,
      );
    },
  );
}
