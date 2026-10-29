import 'package:flutter/material.dart';
import '../../../../domain/proveedores/proveedor.dart';
import '../../../../domain/repositories/margen_promedio_repository.dart';
import '../../../../domain/repositories/proveedor_repository.dart';
import 'widgets/inventory_supplier_card.dart';

class InventorySuppliersTab extends StatefulWidget {
  const InventorySuppliersTab({
    required this.repository,
    required this.onOpen,
    required this.onAdd,
    this.margenPromedioRepository,
    super.key,
  });
  final ProveedorRepository repository;
  final MargenPromedioRepository? margenPromedioRepository;
  final ValueChanged<Proveedor> onOpen;
  final VoidCallback onAdd;

  @override
  State<InventorySuppliersTab> createState() => _InventorySuppliersTabState();
}

class _InventorySuppliersTabState extends State<InventorySuppliersTab> {
  late Stream<List<Proveedor>> _suppliers;
  late Stream<Map<String, double>> _margenes;

  @override
  void initState() {
    super.initState();
    _bindStreams();
  }

  @override
  void didUpdateWidget(InventorySuppliersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.margenPromedioRepository != widget.margenPromedioRepository) {
      _bindStreams();
    }
  }

  void _bindStreams() {
    _suppliers = widget.repository.watchProveedores();
    _margenes =
        widget.margenPromedioRepository?.watchMargenPromedioPorProveedor() ??
        Stream.value(const <String, double>{});
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
      return StreamBuilder<Map<String, double>>(
        stream: _margenes,
        builder: (context, margenSnapshot) {
          final margenes = margenSnapshot.data ?? const <String, double>{};
          final cargando =
              widget.margenPromedioRepository != null &&
              !margenSnapshot.hasData &&
              !margenSnapshot.hasError;
          final error = margenSnapshot.hasError;
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: suppliers.length,
            itemBuilder: (_, index) {
              final supplier = suppliers[index];
              return InventorySupplierCard(
                proveedor: supplier,
                margenPromedioPorcentaje: margenes[supplier.id],
                margenCargando: cargando,
                margenError: error,
                onOpen: () => widget.onOpen(supplier),
              );
            },
          );
        },
      );
    },
  );
}
