import 'package:flutter/material.dart';

import '../../../application/commands/articulos/producto_command_service.dart';
import '../../../application/commands/inventario/crear_recurso_inventario_command.dart';
import '../../../application/commands/inventario/inventory_command_service.dart';
import '../../../application/commands/inventario/registrar_movimiento_inventario_command.dart';
import '../../../application/config/app_config_controller.dart';
import '../../../domain/articulos/nombre_variante.dart';
import '../../../domain/repositories/producto_repository.dart';
import '../../../domain/repositories/proveedor_repository.dart';
import '../../../domain/repositories/recurso_inventario_repository.dart';
import '../../../domain/repositories/unidad_inventario_repository.dart';
import '../gestion_inventario/articulos/models/articulo_form_command.dart';
import '../gestion_inventario/articulos/models/articulo_form_result.dart';
import '../gestion_inventario/articulos/models/articulo_preview_form.dart';
import '../gestion_inventario/articulos/widgets/variant_editor_screen.dart';

/// Coordina la edición definitiva de una variante desde el informe.
class RemainingStockVariantEditor {
  const RemainingStockVariantEditor({
    required this.repository,
    required this.commands,
    required this.resources,
    required this.units,
    required this.inventoryCommands,
    this.suppliers,
    this.config,
  });

  final ProductoRepository repository;
  final ProductoCommandService commands;
  final RecursoInventarioRepository resources;
  final UnidadInventarioRepository units;
  final InventoryCommandService inventoryCommands;
  final ProveedorRepository? suppliers;
  final AppConfigController? config;

  Future<void> open(
    BuildContext context, {
    required String productoId,
    required String varianteId,
  }) async {
    // El repositorio excluye artículos y variantes inactivos. No usar los datos
    // del listado como base: pueden haber cambiado desde su última emisión.
    final detail = await repository.obtenerDetalle(productoId);
    final selected = detail?.variantes
        .where((variant) => variant.id == varianteId)
        .firstOrNull;
    if (detail == null ||
        detail.lastEventId == null ||
        selected == null ||
        selected.inventoryItemId == null) {
      throw StateError('La variante ya no está disponible.');
    }
    final currentResources = await resources.watchRecursos().first;
    final linked = currentResources
        .where((resource) => resource.id == selected.inventoryItemId)
        .firstOrNull;
    if (linked == null ||
        !linked.activo ||
        !linked.unidadPredeterminada.activa) {
      throw StateError('El recurso de la variante ya no está disponible.');
    }
    final inventoryUnits = (await units.obtenerUnidadesActivas()).toList();
    final linkedUnit = linked.unidadPredeterminada;
    if (!inventoryUnits.any((unit) => unit.id == linkedUnit.id)) {
      inventoryUnits.add(linkedUnit);
    }
    final saleUnitId = detail.saleConfiguration.saleUnitId;
    if (saleUnitId != null &&
        !inventoryUnits.any((unit) => unit.id == saleUnitId)) {
      final saleUnit = await units.obtenerUnidadPorId(saleUnitId);
      if (saleUnit == null) throw StateError('Unidad de venta no disponible.');
      inventoryUnits.add(saleUnit);
    }
    final initial = ArticuloPreviewForm.fromDetalle(detail, currentResources);
    final variant = initial.variantes.singleWhere((v) => v.id == varianteId);
    final existingNameKeys = {
      for (final other in initial.variantes)
        if (other.id != varianteId)
          ?NombreVariante.fromInput(other.nombre).nameKey,
    };
    if (!context.mounted || ModalRoute.of(context)?.isCurrent != true) return;
    await Navigator.of(context).push<VariantEditorResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => VariantEditorScreen(
          initialValue: variant,
          canDelete: false,
          existingNameKeys: existingNameKeys,
          productName: initial.nombre,
          saleConfiguration: initial.saleConfiguration,
          inventoryUnit: linkedUnit,
          inventoryUnits: inventoryUnits,
          inventoryResourceRepository: resources,
          proveedorRepository: suppliers,
          appConfigController: config,
          onCreateInventoryResource: (result) => inventoryCommands.crearRecurso(
            CrearRecursoInventarioCommand(
              nombre: result.nombre,
              defaultUnitId: result.unidad.id,
              quantityDeltaAtomic: result.quantityDeltaAtomic,
              movementReason: result.movementReason,
            ),
          ),
          onRegisterInventoryMovement: (id, movement) =>
              inventoryCommands.registrarMovimiento(
                RegistrarMovimientoInventarioCommand(
                  inventoryItemId: id,
                  movementType: movement.movementType,
                  quantityDeltaAtomic: movement.quantityDeltaAtomic,
                  movementReason: movement.reason,
                ),
              ),
          onSave: (edited) async {
            final result = ArticuloFormResult(
              nombre: initial.nombre,
              categoriaId: initial.categoriaId,
              saleConfiguration: initial.saleConfiguration,
              variantes: [
                for (final other in initial.variantes)
                  other.id == varianteId ? edited : other,
              ],
            );
            await commands.actualizarArticulo(
              productId: productoId,
              // Esta base permanece fija incluso después de un error.
              baseEventId: detail.lastEventId!,
              variantIds: result.variantes.map((v) => v.id).toList(),
              command: result.toCommand(),
            );
          },
        ),
      ),
    );
  }
}
