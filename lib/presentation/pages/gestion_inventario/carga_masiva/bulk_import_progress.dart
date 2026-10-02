import 'package:flutter/material.dart';

import '../../../../application/import/articulo_import_progreso.dart';

/// Avance de los lotes y reporte de los productos que no llegaron a guardarse.
class BulkImportProgress extends StatelessWidget {
  const BulkImportProgress({required this.progreso, super.key});

  final ArticuloImportProgreso progreso;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('bulk_import_progress'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            progreso.terminado ? 'Carga finalizada' : 'Importando artículos',
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progreso.lotesTotales == 0
                ? 1
                : progreso.lotesProcesados / progreso.lotesTotales,
          ),
          const SizedBox(height: 8),
          Text('Lotes: ${progreso.lotesProcesados}/${progreso.lotesTotales}'),
          Text(
            'Artículos importados: ${progreso.productosImportados}/${progreso.productosTotales}',
          ),
          Text('Artículos fallidos: ${progreso.productosFallidos}'),
          for (final fallo in progreso.lotesFallidos) ...[
            const SizedBox(height: 8),
            Text(
              'Lote ${fallo.numero}: ${fallo.productos.length} artículos revertidos. '
              'Líneas: ${fallo.lineas.join(', ')}. ${fallo.motivo}',
            ),
            Text('Artículos: ${fallo.productos.join(', ')}'),
          ],
        ],
      ),
    ),
  );
}
