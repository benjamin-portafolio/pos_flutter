import 'package:flutter/material.dart';

import '../../../../domain/proveedores/replenishment_candidate.dart';
import 'supplier_order_forms.dart';

class SupplierOrderVariantSearchScreen extends StatefulWidget {
  const SupplierOrderVariantSearchScreen({
    required this.supplierName,
    required this.candidates,
    super.key,
  });

  final String supplierName;
  final List<ReplenishmentCandidate> candidates;

  @override
  State<SupplierOrderVariantSearchScreen> createState() =>
      _SupplierOrderVariantSearchScreenState();
}

class _SupplierOrderVariantSearchScreenState
    extends State<SupplierOrderVariantSearchScreen> {
  String search = '';

  @override
  Widget build(BuildContext context) {
    final results = widget.candidates
        .where(
          (c) => '${c.productName} ${c.variantName ?? ''}'
              .toLowerCase()
              .contains(search),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Agregar variante')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Proveedor: ${widget.supplierName}'),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Buscar producto o variante',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) =>
                  setState(() => search = value.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        widget.candidates.isEmpty
                            ? 'No hay variantes disponibles para agregar de este proveedor.'
                            : 'No se encontraron variantes.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final candidate = results[index];
                      return ListTile(
                        key: ValueKey(candidate.variantId),
                        title: Text(candidate.productName),
                        subtitle: Text(
                          [
                            if (candidate.variantName != null)
                              candidate.variantName!,
                            'Existencias: ${candidateQuantity(candidate, candidate.balanceAtomic)} ${candidate.unitSymbol}',
                            'Precio de compra: \$${orderMoney(candidate.priceMinor)} por ${candidateQuantity(candidate, candidate.referenceAtomic)} ${candidate.unitSymbol}',
                          ].join('\n'),
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(context, candidate),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
