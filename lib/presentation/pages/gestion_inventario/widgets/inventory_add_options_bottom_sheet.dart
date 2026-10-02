import 'package:flutter/material.dart';

class InventoryAddOptionsBottomSheet extends StatelessWidget {
  const InventoryAddOptionsBottomSheet({
    required this.onAddArticle,
    required this.onAddCategory,
    required this.onAddInventoryResource,
    this.onBulkImport,
    super.key,
  });

  final VoidCallback onAddArticle;
  final VoidCallback onAddCategory;
  final VoidCallback onAddInventoryResource;
  final VoidCallback? onBulkImport;

  static Future<void> show({
    required BuildContext context,
    required VoidCallback onAddArticle,
    required VoidCallback onAddCategory,
    required VoidCallback onAddInventoryResource,
    VoidCallback? onBulkImport,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      // El menú crece con cada opción y en pantallas bajas no cabe entero. Con
      // scroll controlled la hoja toma hasta el alto disponible y el contenido
      // se desplaza en vez de desbordar.
      isScrollControlled: true,
      builder: (_) => InventoryAddOptionsBottomSheet(
        onAddArticle: onAddArticle,
        onAddCategory: onAddCategory,
        onAddInventoryResource: onAddInventoryResource,
        onBulkImport: onBulkImport,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      // El menú crece con cada opción y en pantallas bajas no cabe entero. El
      // alto está acotado y el contenido se desplaza, para que agregar una
      // opción no produzca un desbordamiento.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _InventoryAddOption(
                        key: const Key('add_article_option'),
                        label: 'Añadir artículo',
                        onTap: () {
                          Navigator.of(context).pop();
                          onAddArticle();
                        },
                      ),
                    ),
                    Expanded(
                      child: _InventoryAddOption(
                        key: const Key('add_category_option'),
                        label: 'Añadir categoría',
                        onTap: () {
                          Navigator.of(context).pop();
                          onAddCategory();
                        },
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: const _InventoryAddOption(
                        key: Key('add_modifier_option'),
                        label: 'Añadir modificador',
                      ),
                    ),
                    Expanded(
                      child: _InventoryAddOption(
                        key: const Key('add_inventory_resource_option'),
                        label: 'Añadir recurso de inventario',
                        onTap: () {
                          Navigator.of(context).pop();
                          onAddInventoryResource();
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  width: double.infinity,
                  child: _InventoryAddOption(
                    key: const Key('bulk_edit_option'),
                    label: 'Edición masiva',
                  ),
                ),
                if (onBulkImport != null)
                  SizedBox(
                    width: double.infinity,
                    child: _InventoryAddOption(
                      key: const Key('bulk_import_option'),
                      label: 'Carga masiva',
                      onTap: () {
                        Navigator.of(context).pop();
                        onBulkImport!();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InventoryAddOption extends StatelessWidget {
  const _InventoryAddOption({required this.label, this.onTap, super.key});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: const RoundedRectangleBorder(),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 76,
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
    );
  }
}
