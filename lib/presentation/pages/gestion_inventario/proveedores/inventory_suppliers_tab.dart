import 'package:flutter/material.dart';
import '../../../../domain/proveedores/proveedor.dart';
import '../../../../domain/repositories/proveedor_repository.dart';
import 'widgets/inventory_supplier_card.dart';

class InventorySuppliersTab extends StatefulWidget {
  const InventorySuppliersTab({
    required this.repository,
    required this.onOpen,
    required this.onAdd,
    super.key,
  });
  final ProveedorRepository repository;
  final ValueChanged<Proveedor> onOpen;
  final VoidCallback onAdd;

  @override
  State<InventorySuppliersTab> createState() => _InventorySuppliersTabState();
}

class _InventorySuppliersTabState extends State<InventorySuppliersTab> {
  late Stream<List<Proveedor>> _suppliers;

  @override
  void initState() {
    super.initState();
    _suppliers = widget.repository.watchProveedores();
  }

  @override
  void didUpdateWidget(InventorySuppliersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _suppliers = widget.repository.watchProveedores();
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Proveedor>>(
    stream: _suppliers,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(
          key: Key('suppliers_error'),
          child: Text('No se pudieron cargar los proveedores.'),
        );
      }
      if (!snapshot.hasData) {
        return const Center(
          key: Key('suppliers_loading'),
          child: CircularProgressIndicator(),
        );
      }
      final suppliers = snapshot.data!;
      if (suppliers.isEmpty) {
        return Center(
          key: const Key('suppliers_empty'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Aún no hay proveedores.'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: widget.onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Añadir proveedor'),
              ),
            ],
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: suppliers.length,
        itemBuilder: (_, index) => InventorySupplierCard(
          proveedor: suppliers[index],
          onOpen: () => widget.onOpen(suppliers[index]),
        ),
      );
    },
  );
}
