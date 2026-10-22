import 'package:flutter/material.dart';

import '../../../../application/commands/articulos/crear_articulo_command.dart';
import '../../../../application/commands/inventario/crear_recurso_inventario_command.dart';
import '../../../../application/commands/inventario/inventory_command_service.dart';
import '../../../../application/config/app_config_controller.dart';
import '../../../../core/di/injection.dart';
import '../../../../domain/repositories/categoria_repository.dart';
import '../../../../domain/repositories/proveedor_repository.dart';
import '../../../../domain/repositories/recurso_inventario_repository.dart';
import '../../../../domain/repositories/unidad_inventario_repository.dart';
import 'article_form_screen.dart';
import 'models/articulo_form_command.dart';

/// Abre el alta habitual desde Caja con el código leído en la primera variante.
class BarcodeArticleCreationFlow {
  const BarcodeArticleCreationFlow({required this.create});

  final Future<void> Function(CrearArticuloCommand) create;

  Future<bool> run(
    BuildContext context,
    String code, {
    required bool Function() canContinue,
  }) async {
    final categories = await getIt<CategoriaRepository>().obtenerCategorias();
    final units = await getIt<UnidadInventarioRepository>()
        .obtenerUnidadesActivas();
    if (!context.mounted ||
        !canContinue() ||
        ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    var persisted = false;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ArticleFormScreen(
          categorias: categories,
          unidadesVenta: units,
          initialBarcode: code,
          proveedorRepository: getIt<ProveedorRepository>(),
          appConfigController: getIt<AppConfigController>(),
          inventoryResourceRepository: getIt<RecursoInventarioRepository>(),
          onCreateInventoryResource: (result) =>
              getIt<InventoryCommandService>().crearRecurso(
                CrearRecursoInventarioCommand(
                  nombre: result.nombre,
                  defaultUnitId: result.unidad.id,
                  quantityDeltaAtomic: result.quantityDeltaAtomic,
                  movementReason: result.movementReason,
                ),
              ),
          onSave: (result) async {
            if (!canContinue()) throw StateError('La lectura terminó.');
            await create(result.toCommand());
            persisted = true;
          },
        ),
      ),
    );
    return saved == true && persisted;
  }
}
