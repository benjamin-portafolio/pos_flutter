import 'package:flutter/material.dart';

import '../../../../../domain/articulos/proveedor_variante.dart';
import '../../../../../domain/proveedores/proveedor.dart';
import '../../../../../domain/repositories/proveedor_repository.dart';
import '../models/proveedor_precio_form.dart';
import '../models/proveedor_precio_input.dart';

/// Consulta de precios del borrador, con nombres obtenidos del catálogo local.
class VariantSuppliersSummary extends StatefulWidget {
  const VariantSuppliersSummary({
    required this.repository,
    required this.proveedores,
    required this.priceBasis,
    super.key,
  });

  final ProveedorRepository repository;
  final List<ProveedorVariante> proveedores;
  final String priceBasis;

  @override
  State<VariantSuppliersSummary> createState() =>
      _VariantSuppliersSummaryState();
}

class _VariantSuppliersSummaryState extends State<VariantSuppliersSummary> {
  late Stream<List<Proveedor>> _catalog;

  @override
  void initState() {
    super.initState();
    _catalog = widget.repository.watchProveedores();
  }

  @override
  void didUpdateWidget(VariantSuppliersSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _catalog = widget.repository.watchProveedores();
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Proveedor>>(
    stream: _catalog,
    builder: (context, snapshot) {
      final names = {
        for (final p in snapshot.data ?? <Proveedor>[]) p.id: p.nombre,
      };
      return Column(
        key: const Key('variant_suppliers_summary'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('PROVEEDORES', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(widget.priceBasis),
          if (widget.proveedores.isEmpty)
            const Text('Sin proveedores seleccionados.')
          else ...[
            if (snapshot.hasError)
              const Text('No se pudieron cargar los nombres de proveedores.'),
            for (final relation in widget.proveedores)
              Padding(
                key: Key('variant_supplier_summary_${relation.proveedorId}'),
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${names[relation.proveedorId] ?? 'Proveedor ${relation.proveedorId}'}'
                  ' · \$${ProveedorPrecioInput.format(relation.precioInformadoMenor)}'
                  ' · ${ProveedorPrecioForm.formatDate(relation.fechaInformadaMs)}',
                ),
              ),
          ],
        ],
      );
    },
  );
}
