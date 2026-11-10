import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/import/articulo_catalog_import_service.dart';
import 'package:pos_flutter/application/import/articulo_import_eliminacion.dart';
import 'package:pos_flutter/application/import/articulo_import_producto_local.dart';
import 'package:pos_flutter/application/import/articulo_import_variante_local.dart';
import 'package:pos_flutter/domain/articulos/sale_mode.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/carga_masiva/bulk_import_review.dart';

void main() {
  testWidgets(
    'muestra producto completo y variantes a eliminar antes de confirmar',
    (tester) async {
      final report = ArticuloImportReporte(
        eliminaciones: [
          ArticuloImportEliminacion(
            lineas: const [2],
            actual: ArticuloImportProductoLocal(
              id: 'P',
              activo: true,
              nombre: 'Camiseta',
              modoVenta: SaleMode.unit,
              variantes: [
                for (final nombre in ['Chica', 'Grande'])
                  ArticuloImportVarianteLocal(
                    id: nombre,
                    productId: 'P',
                    activa: true,
                    sortOrder: 0,
                    nombre: nombre,
                    precioVentaMinor: 2500,
                    seguimientoExistencias: false,
                  ),
              ],
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BulkImportReview(reporte: report, mostrarSeleccion: false),
            ),
          ),
        ),
      );
      expect(
        find.textContaining('Eliminaciones: 1 productos completos'),
        findsOneWidget,
      );
      expect(find.textContaining('Nuevos: 0 productos'), findsOneWidget);
      expect(find.textContaining('Con cambios: 0 productos'), findsOneWidget);
      expect(
        find.textContaining('Eliminar producto completo: Camiseta (P)'),
        findsOneWidget,
      );
      expect(
        find.textContaining('2 variantes: Chica (Chica), Grande (Grande)'),
        findsOneWidget,
      );
    },
  );
}
