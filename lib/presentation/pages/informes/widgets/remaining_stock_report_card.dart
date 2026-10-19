import 'package:flutter/material.dart';

import '../../../../domain/articulos/articulo_listado.dart';
import '../../../../domain/repositories/producto_repository.dart';
import '../models/remaining_stock_item.dart';
import '../remaining_stock_screen.dart';

class RemainingStockReportCard extends StatefulWidget {
  const RemainingStockReportCard({required this.repository, super.key});

  final ProductoRepository repository;

  @override
  State<RemainingStockReportCard> createState() =>
      _RemainingStockReportCardState();
}

class _RemainingStockReportCardState extends State<RemainingStockReportCard> {
  late Stream<List<ArticuloListado>> _articles = widget.repository
      .watchArticulos();

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => RemainingStockScreen(repository: widget.repository),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EXISTENCIAS RESTANTES',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<ArticuloListado>>(
              stream: _articles,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('No se pudieron cargar las existencias.'),
                      TextButton(
                        onPressed: () => setState(
                          () => _articles = widget.repository.watchArticulos(),
                        ),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting ||
                    !snapshot.hasData) {
                  return const Text('Cargando variantes…');
                }
                final items = RemainingStockItem.fromArticles(snapshot.data!);
                final count = items.length;
                final lowCount = items.where((item) => item.isLow).length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count ${count == 1 ? 'variante' : 'variantes'} con seguimiento',
                    ),
                    Text('Existencias bajas: $lowCount'),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}
