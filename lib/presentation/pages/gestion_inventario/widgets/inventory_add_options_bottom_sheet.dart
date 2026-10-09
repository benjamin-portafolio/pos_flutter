import 'package:flutter/material.dart';

class InventoryAddOptionsBottomSheet extends StatelessWidget {
  const InventoryAddOptionsBottomSheet({
    required this.onAddArticle,
    required this.onAddCategory,
    required this.onAddInventoryResource,
    this.onBulkImport,
    this.onAddSupplier,
    super.key,
  });

  final VoidCallback onAddArticle;
  final VoidCallback onAddCategory;
  final VoidCallback onAddInventoryResource;
  final VoidCallback? onBulkImport;
  final VoidCallback? onAddSupplier;

  static Future<void> show({
    required BuildContext context,
    required VoidCallback onAddArticle,
    required VoidCallback onAddCategory,
    required VoidCallback onAddInventoryResource,
    VoidCallback? onBulkImport,
    VoidCallback? onAddSupplier,
    Stream<bool>? supplierAvailability,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => StreamBuilder<bool>(
      stream: supplierAvailability,
      initialData: onAddSupplier != null,
      builder: (_, snapshot) => InventoryAddOptionsBottomSheet(
        onAddArticle: onAddArticle,
        onAddCategory: onAddCategory,
        onAddInventoryResource: onAddInventoryResource,
        onBulkImport: onBulkImport,
        onAddSupplier: snapshot.data == true ? onAddSupplier : null,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final options = [
      _option(context, 'add_article_option', 'Añadir artículo', onAddArticle),
      _option(
        context,
        'add_category_option',
        'Añadir categoría',
        onAddCategory,
      ),
      _option(context, 'add_modifier_option', 'Añadir modificador', null),
      _option(
        context,
        'add_inventory_resource_option',
        'Añadir recurso de inventario',
        onAddInventoryResource,
      ),
      if (onAddSupplier != null)
        _option(
          context,
          'add_supplier_option',
          'Añadir proveedor',
          onAddSupplier,
        ),
      _option(context, 'bulk_edit_option', 'Edición masiva', null),
      if (onBulkImport != null)
        _option(context, 'bulk_import_option', 'Carga masiva', onBulkImport),
    ];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: LayoutBuilder(
            builder: (_, constraints) {
              final columns = constraints.maxWidth < 480 ? 1 : 2;
              return Wrap(
                children: [
                  for (final option in options)
                    SizedBox(
                      width: constraints.maxWidth / columns,
                      child: option,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _option(
    BuildContext context,
    String key,
    String label,
    VoidCallback? action,
  ) => _InventoryAddOption(
    key: Key(key),
    label: label,
    onTap: action == null
        ? null
        : () {
            Navigator.of(context).pop();
            action();
          },
  );
}

class _InventoryAddOption extends StatelessWidget {
  const _InventoryAddOption({required this.label, this.onTap, super.key});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    shape: const RoundedRectangleBorder(),
    child: InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 76),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
