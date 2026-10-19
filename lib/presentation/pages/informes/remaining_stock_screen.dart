import 'package:flutter/material.dart';

import '../../../application/commands/articulos/producto_command_service.dart';
import '../../../application/commands/inventario/inventory_command_service.dart';
import '../../../application/config/app_config_controller.dart';
import '../../../core/di/injection.dart';
import '../../../domain/articulos/articulo_listado.dart';
import '../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../domain/repositories/producto_repository.dart';
import '../../../domain/repositories/proveedor_repository.dart';
import '../../../domain/repositories/recurso_inventario_repository.dart';
import '../../../domain/repositories/unidad_inventario_repository.dart';
import 'models/remaining_stock_item.dart';
import 'remaining_stock_variant_editor.dart';

class RemainingStockScreen extends StatefulWidget {
  const RemainingStockScreen({
    required this.repository,
    this.variantEditor,
    super.key,
  });

  final ProductoRepository repository;
  final RemainingStockVariantEditor? variantEditor;

  @override
  State<RemainingStockScreen> createState() => _RemainingStockScreenState();
}

class _RemainingStockScreenState extends State<RemainingStockScreen> {
  final _scrollController = ScrollController();
  bool _openingVariant = false;
  bool _onlyLowStock = false;
  late Stream<List<ArticuloListado>> _articles = widget.repository
      .watchArticulos();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _editVariant(RemainingStockItem item) async {
    if (_openingVariant) return;
    _openingVariant = true;
    try {
      final editor =
          widget.variantEditor ??
          RemainingStockVariantEditor(
            repository: widget.repository,
            commands: getIt<ProductoCommandService>(),
            resources: getIt<RecursoInventarioRepository>(),
            units: getIt<UnidadInventarioRepository>(),
            inventoryCommands: getIt<InventoryCommandService>(),
            suppliers: getIt.isRegistered<ProveedorRepository>()
                ? getIt<ProveedorRepository>()
                : null,
            config: getIt.isRegistered<AppConfigController>()
                ? getIt<AppConfigController>()
                : null,
          );
      await editor.open(
        context,
        productoId: item.productoId,
        varianteId: item.variant.varianteId,
      );
    } catch (_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo cargar la variante. Puede que ya no esté disponible. '
            'Intenta de nuevo.',
          ),
        ),
      );
    } finally {
      _openingVariant = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Existencias restantes')),
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Inventario actual'),
          ),
          Expanded(
            child: StreamBuilder<List<ArticuloListado>>(
              stream: _articles,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'No se pudieron cargar las existencias.',
                            textAlign: TextAlign.center,
                          ),
                          TextButton(
                            onPressed: () => setState(
                              () => _articles = widget.repository
                                  .watchArticulos(),
                            ),
                            child: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting ||
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = RemainingStockItem.fromArticles(snapshot.data!);
                final lowItems = items.where((item) => item.isLow).toList();
                final visible = _onlyLowStock ? lowItems : items;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ChoiceChip(
                            label: const Text('Todas'),
                            selected: !_onlyLowStock,
                            onSelected: (_) =>
                                setState(() => _onlyLowStock = false),
                          ),
                          ChoiceChip(
                            label: const Text('Existencias bajas'),
                            selected: _onlyLowStock,
                            onSelected: (_) =>
                                setState(() => _onlyLowStock = true),
                          ),
                          Text('Existencias bajas: ${lowItems.length}'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: visible.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  _onlyLowStock
                                      ? 'No hay variantes con existencias bajas.'
                                      : 'No hay variantes con seguimiento de existencias.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              itemCount: visible.length,
                              itemBuilder: (context, index) =>
                                  _RemainingStockRow(
                                    key: ValueKey(
                                      visible[index].variant.varianteId,
                                    ),
                                    item: visible[index],
                                    onTap: () => _editVariant(visible[index]),
                                  ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _RemainingStockRow extends StatelessWidget {
  const _RemainingStockRow({
    required this.item,
    required this.onTap,
    super.key,
  });

  final RemainingStockItem item;
  final VoidCallback onTap;
  static const _quantityCodec = InventoryQuantityCodec();

  @override
  Widget build(BuildContext context) {
    final variantName = item.variant.nombre?.trim() ?? '';
    final inventory = item.inventory;
    final unit = inventory.unidadPredeterminada;
    final quantity = _quantityCodec.formatAtomic(
      inventory.existenciaAtomica,
      unit,
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.articleName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (variantName.isNotEmpty) Text(variantName),
                  if (item.isLow) const Chip(label: Text('Existencia baja')),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Flexible(
              flex: 2,
              child: Align(
                alignment: Alignment.centerRight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$quantity ${unit.simbolo}',
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      item.minimumStockAtomic == null
                          ? 'Sin mínimo'
                          : 'Mínimo: ${_quantityCodec.formatAtomic(item.minimumStockAtomic!, unit)} ${unit.simbolo}',
                      textAlign: TextAlign.end,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
