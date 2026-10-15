import 'package:flutter/material.dart';

import '../../../../domain/articulos/articulo_listado.dart';
import '../../../../domain/repositories/producto_repository.dart';
import '../../articulos/models/article_search_item.dart';

/// Selecciona una variante del catálogo sin operaciones ni estado de ventas.
class InventoryBarcodeVariantSelector extends StatefulWidget {
  const InventoryBarcodeVariantSelector({
    required this.repository,
    required this.code,
    super.key,
  });

  final ProductoRepository repository;
  final String code;

  @override
  State<InventoryBarcodeVariantSelector> createState() =>
      _InventoryBarcodeVariantSelectorState();
}

class _InventoryBarcodeVariantSelectorState
    extends State<InventoryBarcodeVariantSelector> {
  final _search = TextEditingController();
  late Stream<List<ArticuloListado>> _articles;

  @override
  void initState() {
    super.initState();
    _articles = widget.repository.watchArticulos();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Elegir variante')),
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Código nuevo: ${widget.code}'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const Key('inventory_barcode_search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Buscar artículo o variante',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ArticuloListado>>(
              stream: _articles,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('No se pudieron cargar los artículos.'),
                        TextButton(
                          onPressed: () => setState(() {
                            _articles = widget.repository.watchArticulos();
                          }),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final results = ArticleSearchItem.search(
                  snapshot.data!,
                  _search.text,
                );
                if (results.isEmpty) {
                  return Center(
                    child: Text(
                      _search.text.trim().isEmpty
                          ? 'No hay variantes activas.'
                          : 'No se encontraron variantes.',
                    ),
                  );
                }
                return ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final item = results[index];
                    final name = item.variant.nombre?.trim();
                    final price = item.variant.precioVentaMenor;
                    return ListTile(
                      key: ValueKey(
                        'inventory_barcode_target_${item.variant.varianteId}',
                      ),
                      title: Text(item.article.nombre),
                      subtitle: Text(
                        name == null || name.isEmpty
                            ? 'Variante sin nombre'
                            : name,
                      ),
                      trailing: Text(
                        '\$${price ~/ 100}.${(price % 100).toString().padLeft(2, '0')}',
                      ),
                      onTap: () {
                        if (ModalRoute.of(context)?.isCurrent == true) {
                          Navigator.of(context).pop(item);
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
