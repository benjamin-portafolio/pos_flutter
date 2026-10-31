import '../drift/drift_producto_projection_store.dart';
import '../../../application/import/articulo_catalog_import_service.dart';
import '../../../application/import/articulo_import_catalog_reader.dart';
import '../../../application/import/articulo_import_producto_local.dart';
import '../../../application/import/articulo_import_solicitud.dart';
import '../../../application/import/articulo_import_variante_local.dart';
import '../../../domain/articulos/sale_mode.dart';
import '../../../domain/inventario/dimension_unidad.dart';
import '../../../domain/inventario/unidad_inventario.dart';
import '../drift/app_database.dart';

/// Foto de revisión por conjuntos, sin saldos, recetas, proveedores ni eventos.
/// Incluye inactivos para distinguir una identidad retirada de una alta.
class DriftArticuloImportCatalogReader implements ArticuloImportCatalogReader {
  const DriftArticuloImportCatalogReader(this.db);
  final AppDatabase db;

  @override
  Future<ArticuloImportCatalogo> leer(ArticuloImportSolicitud solicitud) =>
      db.transaction(() async {
        final nombres =
            await (db.selectOnly(db.products)
                  ..addColumns([db.products.name])
                  ..where(db.products.active.equals(true)))
                .get();
        final categorias = await (db.select(
          db.categories,
        )..where((t) => t.active.equals(true))).get();
        final unidades = await (db.select(
          db.units,
        )..where((t) => t.active.equals(true))).get();
        final productos = solicitud.productIds.isEmpty
            ? <ProductRow>[]
            : await (db.select(
                db.products,
              )..where((t) => t.id.isIn(solicitud.productIds))).get();
        // Dos consultas acotadas a 500 IDs cada una: evita 1000 parámetros en
        // SQLite de dispositivos antiguos y conserva la pertenencia real.
        final delProducto = solicitud.productIds.isEmpty
            ? <ProductVariantRow>[]
            : await (db.select(
                db.productVariants,
              )..where((t) => t.productId.isIn(solicitud.productIds))).get();
        final porIdentidad = solicitud.variantIds.isEmpty
            ? <ProductVariantRow>[]
            : await (db.select(
                db.productVariants,
              )..where((t) => t.id.isIn(solicitud.variantIds))).get();
        final baseIds = productos
            .map((p) => p.lastEventId)
            .whereType<String>()
            .toSet();
        final known = <String>{};
        if (baseIds.isNotEmpty) {
          final events = await (db.select(
            db.events,
          )..where((e) => e.eventId.isIn(baseIds))).get();
          for (final e in events) {
            if (DriftProductoProjectionStore.offerPriceKnownFromEvent(e)) {
              known.add(e.aggregateId);
            }
          }
        }
        final variantes = {
          for (final v in [...delProducto, ...porIdentidad])
            v.id: ArticuloImportVarianteLocal(
              id: v.id,
              productId: v.productId,
              activa: v.active,
              sortOrder: v.sortOrder,
              nombre: v.name,
              precioVentaMinor: v.salePriceMinor,
              offerPriceMinor: v.offerPriceMinor,
              knowsOfferPrice:
                  known.contains(v.productId) || v.offerPriceMinor != null,
              precioCosteMinor: v.standardCostMinor,
              codigoBarras: v.barcode,
              seguimientoExistencias: v.inventoryItemId != null,
            ),
        };
        final porProducto = <String, List<ArticuloImportVarianteLocal>>{};
        for (final v in variantes.values) {
          porProducto.putIfAbsent(v.productId, () => []).add(v);
        }
        for (final grupo in porProducto.values) {
          grupo.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        }
        return ArticuloImportCatalogo(
          nombresArticulos: Set.unmodifiable(
            nombres.map((r) => r.read(db.products.name)!),
          ),
          categorias: List.unmodifiable(
            categorias.map(
              (c) => ArticuloImportCategoria(id: c.id, nombre: c.name),
            ),
          ),
          unidades: List.unmodifiable(
            unidades.map(
              (u) => UnidadInventario(
                id: u.unitId,
                code: u.code,
                nombre: u.name,
                simbolo: u.symbol,
                dimension: DimensionUnidad.fromCode(u.dimension),
                factorAtomico: u.atomicFactor,
                maximosDecimales: u.maxFractionDigits,
                activa: u.active,
              ),
            ),
          ),
          variantesPorId: Map.unmodifiable(variantes),
          productosPorId: Map.unmodifiable({
            for (final p in productos)
              p.id: ArticuloImportProductoLocal(
                id: p.id,
                activo: p.active,
                nombre: p.name,
                categoriaId: p.categoryId,
                modoVenta: SaleMode.fromCode(p.saleMode),
                unidadVentaId: p.saleUnitId,
                cantidadReferenciaPrecioAtomic: p.priceReferenceQuantityAtomic,
                lastEventId: p.lastEventId,
                variantes: List.unmodifiable(porProducto[p.id] ?? const []),
              ),
          }),
        );
      });
}
