import 'package:drift/drift.dart' show Value;
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_recipe_component_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/commands/articulos/producto_command_service.dart';
import 'package:pos_flutter/application/commands/articulos/producto_inventory_update_result.dart';
import 'package:pos_flutter/application/commands/inventario/crear_recurso_inventario_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/producto_repository_impl.dart';
import 'package:pos_flutter/data/repositories/proveedor_repository_impl.dart';
import 'package:pos_flutter/data/repositories/recurso_inventario_repository_impl.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/domain/articulos/articulo_detalle.dart';
import 'package:pos_flutter/domain/articulos/articulo_listado.dart';
import 'package:pos_flutter/domain/articulos/proveedor_variante.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/presentation/pages/informes/remaining_stock_variant_editor.dart';

import 'product_supplier_harness.dart';

/// SQLite, comandos y proyecciones reales; solo detiene lecturas y commits.
class RemainingStockFixture {
  RemainingStockFixture({AppMode mode = AppMode.standalone})
    : h = ProductSupplierHarness(mode: mode);

  final ProductSupplierHarness h;
  final detailReads = <String>[];
  final saveBases = <String>[];
  Future<void> Function()? beforeDetail;
  Future<void> Function()? beforeSave;
  Stream<List<ArticuloListado>> Function()? catalog;
  late final products = _Products(this);
  late final commands = _Commands(this);
  late final resources = RecursoInventarioRepositoryImpl(
    inventoryDao: h.db.inventoryDao,
  );
  late final units = UnidadInventarioRepositoryImpl(unitDao: h.db.unitDao);
  late final suppliers = ProveedorRepositoryImpl(h.db.proveedorDao);
  late final editor = RemainingStockVariantEditor(
    repository: products,
    commands: commands,
    resources: resources,
    units: units,
    inventoryCommands: h.tracking.inventoryCommands,
    suppliers: suppliers,
    config: h.tracking.config,
  );
  late String productId;
  late String selectedId;
  late String firstId;
  late String recipeResourceId;
  late String initialBase;
  late int initialEvents;

  Future<void> seed() async {
    const categoryId = '20000000-0000-4000-8000-000000000001';
    // Categoría oficial ya disponible, sin una creación local pendiente.
    await h.db
        .into(h.db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: categoryId,
            name: 'Bebidas',
            sortOrder: 0,
            lastServerSequence: const Value(1),
          ),
        );
    final supplierId = await h.supplier('Distribuidora');
    await h.tracking.inventoryCommands.crearRecurso(
      const CrearRecursoInventarioCommand(
        nombre: 'Harina',
        defaultUnitId: InventoryUnitIds.kilogram,
      ),
    );
    recipeResourceId = (await resources.watchRecursos().first).single.id;
    final quotes = [
      ProveedorVariante(
        proveedorId: supplierId,
        precioInformadoMenor: 1234,
        fechaInformadaMs: 1720000000000,
      ),
    ];
    await h.commands.crearArticulo(
      CrearArticuloCommand.conVariantes(
        nombre: 'Café',
        categoriaId: categoryId,
        saleConfiguration: const UnitSaleConfiguration(),
        variantes: [
          CrearArticuloVarianteCommand.conProveedores(
            nombre: 'Chico',
            precioVenta: '10.01',
            costoEstandar: '0',
            codigoBarras: '0001',
            proveedores: quotes,
            inventoryUnitId: InventoryUnitIds.piece,
            initialStockQuantity: '3',
          ),
          CrearArticuloVarianteCommand.conProveedores(
            nombre: 'Grande',
            precioVenta: '25.50',
            costoEstandar: '11.22',
            codigoBarras: '0002',
            proveedores: quotes,
            inventoryUnitId: InventoryUnitIds.piece,
            initialStockQuantity: '7',
          ),
          CrearArticuloVarianteCommand.conProveedores(
            nombre: 'Receta',
            precioVenta: '30.03',
            costoEstandar: '8.37',
            codigoBarras: '0003',
            proveedores: quotes,
            recipeComponents: [
              CrearArticuloRecipeComponentCommand(
                inventoryItemId: recipeResourceId,
                quantity: '0.125',
              ),
            ],
          ),
          const CrearArticuloVarianteCommand(
            nombre: 'Libre',
            precioVenta: '9.09',
            costoEstandar: null,
            codigoBarras: '0004',
          ),
        ],
      ),
    );
    final article = (await h.repository.watchArticulos().first).single;
    productId = article.productoId;
    firstId = article.variantesActivas.first.varianteId;
    selectedId = article.variantesActivas[1].varianteId;
    initialBase = (await h.repository.obtenerDetalle(productId))!.lastEventId!;
    initialEvents = (await h.db.select(h.db.events).get()).length;
  }
}

class _Products extends ProductoRepositoryImpl {
  _Products(this.fixture) : super(productoDao: fixture.h.db.productoDao);
  final RemainingStockFixture fixture;

  @override
  Future<ArticuloDetalle?> obtenerDetalle(String productoId) async {
    fixture.detailReads.add(productoId);
    await fixture.beforeDetail?.call();
    return super.obtenerDetalle(productoId);
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
  final RemainingStockFixture fixture;

  @override
  Future<ProductoInventoryUpdateResult> actualizarArticulo({
    required String productId,
    required String baseEventId,
    required CrearArticuloCommand command,
    required List<String?> variantIds,
  }) async {
    fixture.saveBases.add(baseEventId);
    await fixture.beforeSave?.call();
    return fixture.h.commands.actualizarArticulo(
      productId: productId,
      baseEventId: baseEventId,
      command: command,
      variantIds: variantIds,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
