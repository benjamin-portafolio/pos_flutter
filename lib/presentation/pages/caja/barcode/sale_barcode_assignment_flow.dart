import 'package:flutter/material.dart';

import '../../../../application/commands/articulos/asignar_codigo_barras_variante_command.dart';
import '../../../../domain/articulos/variante_por_codigo_barras.dart';
import '../../../../domain/repositories/producto_repository.dart';
import '../../articulos/models/article_search_item.dart';
import '../../gestion_inventario/articulos/unknown_barcode_dialog.dart';
import '../../gestion_inventario/articulos/inventory_barcode_matches_dialog.dart';
import '../../gestion_inventario/articulos/inventory_barcode_assignment_screen.dart';
import '../../gestion_inventario/articulos/inventory_barcode_variant_selector.dart';
import 'sale_barcode_assigned_exception.dart';

/// Reutiliza selección y guardado del catálogo antes de continuar la venta.
class SaleBarcodeAssignmentFlow {
  const SaleBarcodeAssignmentFlow({
    required this.repository,
    required this.assign,
    required this.createArticle,
  });

  final Future<bool> Function(BuildContext, String, bool Function())
  createArticle;
  final ProductoRepository repository;
  final Future<void> Function(AsignarCodigoBarrasVarianteCommand) assign;

  Future<VariantePorCodigoBarras?> run(
    BuildContext context,
    String code, {
    required bool Function() canContinue,
  }) async {
    bool active() =>
        context.mounted &&
        canContinue() &&
        ModalRoute.of(context)?.isCurrent == true;

    if (!active()) return null;
    final action = await showDialog<UnknownBarcodeAction>(
      context: context,
      builder: (_) => UnknownBarcodeDialog(code: code, forSale: true),
    );
    if (!context.mounted || !active()) return null;
    if (action == UnknownBarcodeAction.create) {
      final saved = await createArticle(context, code, canContinue);
      if (!saved || !context.mounted || !active()) return null;
      try {
        final matches = await repository.buscarVariantesPorCodigoBarras(code);
        if (!context.mounted || !active()) return null;
        if (matches.isEmpty) {
          throw StateError(
            'El artículo se guardó, pero ya no tiene el código leído.',
          );
        }
        if (matches.length == 1) return matches.single;
        return await showDialog<VariantePorCodigoBarras>(
          context: context,
          builder: (_) => InventoryBarcodeMatchesDialog(matches: matches),
        );
      } catch (error, stack) {
        Error.throwWithStackTrace(SaleBarcodeAssignedException(error), stack);
      }
    }
    if (action != UnknownBarcodeAction.assign) return null;
    final target = await Navigator.of(context).push<ArticleSearchItem>(
      MaterialPageRoute(
        builder: (_) =>
            InventoryBarcodeVariantSelector(repository: repository, code: code),
      ),
    );
    if (!context.mounted || !active() || target == null) return null;
    final saved = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => InventoryBarcodeAssignmentScreen(
          target: target,
          code: code,
          repository: repository,
          confirmationLabel: 'Guardar código y agregar a la venta',
          alreadyAssignedLabel: 'Continuar a la venta',
          description:
              'El código se guardará en el catálogo y se agregará esta variante '
              'a la venta. Si se vende por medida, se solicitará la cantidad.',
          assign: (command) {
            if (!canContinue()) throw StateError('La lectura terminó.');
            return assign(command);
          },
        ),
      ),
    );
    if (!active() || saved == null) return null;
    try {
      final matches = await repository.buscarVariantesPorCodigoBarras(code);
      if (!active()) return null;
      // El código puede ser compartido: continuar solo con el destino elegido.
      final selected = matches
          .where((v) => v.varianteId == target.variant.varianteId)
          .firstOrNull;
      if (selected == null) {
        throw StateError('La variante ya no está disponible.');
      }
      return selected;
    } catch (error, stack) {
      Error.throwWithStackTrace(SaleBarcodeAssignedException(error), stack);
    }
  }
}
