import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/commands/edicion_masiva/edicion_masiva_command_service.dart';
import 'package:pos_flutter/application/edicion_masiva/cambio_explicito.dart';
import 'package:pos_flutter/application/edicion_masiva/cambio_variante_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/clave_variante.dart';
import 'package:pos_flutter/application/edicion_masiva/entrada_mercancia_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/fila_catalogo_masivo.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_diario_edicion_masiva.dart';
import 'package:pos_flutter/data/repositories/drift_catalogo_edicion_masiva.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';

import 'product_supplier_harness.dart';

Future<List<FilaCatalogoMasivo>> seedRecepcion(
  ProductSupplierHarness h, {
  String nombre = 'Recepción',
  bool medido = false,
}) async {
  await h.commands.crearArticulo(
    CrearArticuloCommand.conVariantes(
      nombre: nombre,
      saleConfiguration: medido
          ? MeasuredSaleConfiguration(
              saleUnitId: InventoryUnitIds.gram,
              priceReferenceQuantityAtomic: 1,
            )
          : const UnitSaleConfiguration(),
      variantes: [
        CrearArticuloVarianteCommand(
          nombre: 'Piezas',
          precioVenta: '20',
          costoEstandar: '10',
          codigoBarras: '00123',
          inventoryUnitId: medido
              ? InventoryUnitIds.kilogram
              : InventoryUnitIds.piece,
          initialStockQuantity: '5',
        ),
        CrearArticuloVarianteCommand(
          nombre: 'Peso',
          precioVenta: '30',
          costoEstandar: null,
          inventoryUnitId: medido
              ? InventoryUnitIds.kilogram
              : InventoryUnitIds.piece,
          initialStockQuantity: medido ? '0.5' : '500',
        ),
        CrearArticuloVarianteCommand(
          nombre: 'Sin seguimiento',
          precioVenta: '40',
          costoEstandar: '0',
        ),
      ],
    ),
  );
  final product = (await h.db.select(h.db.products).get()).singleWhere(
    (p) => p.name == nombre,
  );
  return (await DriftCatalogoEdicionMasiva(
      h.db,
    ).buscar()).where((f) => f.clave.productId == product.id).toList()
    ..sort((a, b) => a.nombreVariante!.compareTo(b.nombreVariante!));
}

CambioVarianteMasiva cambioRecepcion(
  FilaCatalogoMasivo f, {
  int? venta,
  int? costo,
  int? cantidad,
}) => CambioVarianteMasiva(
  clave: f.clave,
  baseProducto: f.baseProducto,
  venta: venta == null
      ? const CambioExplicito.conservar()
      : CambioExplicito.establecer(venta),
  costo: costo == null
      ? const CambioExplicito.conservar()
      : CambioExplicito.establecer(costo),
  precioProveedor: null,
  entrada: cantidad == null
      ? null
      : EntradaMercanciaMasiva(base: f.entrada!, cantidadAtomic: cantidad),
);

EdicionMasivaCommandService coordinadorRecepcion(ProductSupplierHarness h) =>
    EdicionMasivaCommandService(
      DriftDiarioEdicionMasiva(
        db: h.db,
        config: h.tracking.config,
        context: h.tracking.context,
      ),
    );

/// Todas las tablas, incluidos respaldos, refs y diario; el orden por rowid hace
/// visible una escritura extra aunque sus importes coincidan con los anteriores.
Future<Map<String, List<Map<String, Object?>>>> fotoRecepcion(
  AppDatabase db,
) async {
  final tables = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .get();
  return {
    for (final table in tables)
      table.read<String>('name'): [
        for (final row
            in await db
                .customSelect(
                  'SELECT * FROM "${table.read<String>('name')}" ORDER BY rowid',
                )
                .get())
          row.data,
      ],
  };
}

Future<FilaCatalogoMasivo> releerRecepcion(
  AppDatabase db,
  ClaveVariante clave,
) async => (await DriftCatalogoEdicionMasiva(db).leer({clave})).filas[clave]!;
