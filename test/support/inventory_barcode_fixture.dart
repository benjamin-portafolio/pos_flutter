import 'package:pos_flutter/application/commands/articulos/asignar_codigo_barras_variante_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/commands/articulos/producto_command_service.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/producto_repository_impl.dart';
import 'package:pos_flutter/domain/articulos/articulo_detalle.dart';
import 'package:pos_flutter/domain/articulos/articulo_listado.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/articulos/variante_por_codigo_barras.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';

import 'product_supplier_harness.dart';

/// Solo los hooks de lectura/guardado se detienen; comandos y SQLite son reales.
class InventoryBarcodeFixture {
  InventoryBarcodeFixture({
    AppDatabase? database,
    AppMode mode = AppMode.standalone,
  }) : h = ProductSupplierHarness(database: database, mode: mode);

  final ProductSupplierHarness h;
  final lookups = <String>[];
  final details = <String>[];
  final assignments = <AsignarCodigoBarrasVarianteCommand>[];
  Future<void> Function()? beforeLookup;
  Future<void> Function()? beforeDetail;
  Future<void> Function()? beforeAssign;
  Stream<List<ArticuloListado>> Function()? catalog;
  late final products = _Products(this);
  late final commands = _Commands(this);
  late List<ArticuloListado> articles;
  late int initialEvents;

  ArticuloListado article(String name) =>
      articles.singleWhere((a) => a.nombre == name);
  String variant(String product, String? name) => article(
    product,
  ).variantesActivas.singleWhere((v) => v.nombre == name).varianteId;

  Future<void> seed() async {
    for (final entry in [
      (
        'Café',
        [
          const CrearArticuloVarianteCommand(
            costoEstandar: null,
            nombre: 'Chico',
            precioVenta: '10',
            codigoBarras: '001',
          ),
          const CrearArticuloVarianteCommand(
            costoEstandar: null,
            nombre: 'Grande',
            precioVenta: '15',
            codigoBarras: '002',
          ),
        ],
      ),
      (
        'Té',
        [
          const CrearArticuloVarianteCommand(
            costoEstandar: null,
            nombre: null,
            precioVenta: '8',
            codigoBarras: '003',
          ),
        ],
      ),
      (
        'Leche',
        [
          const CrearArticuloVarianteCommand(
            costoEstandar: null,
            nombre: 'Entera',
            precioVenta: '20',
            codigoBarras: '003',
          ),
          const CrearArticuloVarianteCommand(
            costoEstandar: null,
            nombre: 'Light',
            precioVenta: '22',
            inventoryUnitId: InventoryUnitIds.piece,
            initialStockQuantity: '4',
          ),
        ],
      ),
      (
        'Agua',
        [
          const CrearArticuloVarianteCommand(
            nombre: null,
            costoEstandar: null,
            precioVenta: '5',
          ),
        ],
      ),
    ]) {
      await h.commands.crearArticulo(
        CrearArticuloCommand.conVariantes(
          nombre: entry.$1,
          saleConfiguration: const UnitSaleConfiguration(),
          variantes: entry.$2,
        ),
      );
    }
    articles = await h.repository.watchArticulos().first;
    await h.tracking.drafts.agregar(
      AgregarProductoBorradorCommand(variantId: variant('Café', 'Chico')),
    );
    initialEvents = (await h.db.select(h.db.events).get()).length;
  }

  Future<void> assignDirect(String product, String? name, String code) async {
    final id = article(product).productoId;
    final detail = (await h.repository.obtenerDetalle(id))!;
    await h.commands.asignarCodigoBarrasVariante(
      AsignarCodigoBarrasVarianteCommand(
        productId: id,
        variantId: variant(product, name),
        baseEventId: detail.lastEventId!,
        codigoBarras: code,
      ),
    );
  }

  Future<Map<String, List<Map<String, Object?>>>> state() async => {
    for (final table in h.db.allTables)
      table.actualTableName: await h.db
          .customSelect(
            'SELECT * FROM "${table.actualTableName}" ORDER BY rowid',
          )
          .get()
          .then((rows) => rows.map((row) => row.data).toList()),
  };
}

class _Products extends ProductoRepositoryImpl {
  _Products(this.fixture) : super(productoDao: fixture.h.db.productoDao);
  final InventoryBarcodeFixture fixture;

  @override
  Future<List<VariantePorCodigoBarras>> buscarVariantesPorCodigoBarras(
    String code,
  ) async {
    fixture.lookups.add(code);
    await fixture.beforeLookup?.call();
    return super.buscarVariantesPorCodigoBarras(code);
  }

  @override
  Future<ArticuloDetalle?> obtenerDetalle(String id) async {
    fixture.details.add(id);
    await fixture.beforeDetail?.call();
    return super.obtenerDetalle(id);
  }

  @override
  Stream<List<ArticuloListado>> watchArticulos({
    String busqueda = '',
    Set<String> categoriaIds = const {},
    bool incluirSinCategoria = false,
  }) =>
      fixture.catalog?.call() ??
      super.watchArticulos(
        busqueda: busqueda,
        categoriaIds: categoriaIds,
        incluirSinCategoria: incluirSinCategoria,
      );
}

class _Commands implements ProductoCommandService {
  _Commands(this.fixture);
  final InventoryBarcodeFixture fixture;

  @override
  Future<void> crearArticulo(CrearArticuloCommand command) =>
      fixture.h.commands.crearArticulo(command);

  @override
  Future<void> asignarCodigoBarrasVariante(
    AsignarCodigoBarrasVarianteCommand command,
  ) async {
    fixture.assignments.add(command);
    await fixture.beforeAssign?.call();
    await fixture.h.commands.asignarCodigoBarrasVariante(command);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
