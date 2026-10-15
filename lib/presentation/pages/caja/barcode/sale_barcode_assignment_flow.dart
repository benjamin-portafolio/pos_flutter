import 'package:flutter/material.dart';

import '../../../../application/commands/articulos/asignar_codigo_barras_variante_command.dart';
import '../../../../domain/articulos/variante_por_codigo_barras.dart';
import '../../../../domain/repositories/producto_repository.dart';
import '../../articulos/models/article_search_item.dart';
import '../../gestion_inventario/articulos/inventory_barcode_assignment_screen.dart';
import '../../gestion_inventario/articulos/inventory_barcode_variant_selector.dart';
import 'sale_barcode_assigned_exception.dart';

/// Reutiliza selección y guardado del catálogo antes de continuar la venta.
class SaleBarcodeAssignmentFlow {
  const SaleBarcodeAssignmentFlow({
    required this.repository,
    required this.assign,
  });

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
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Código no encontrado'),
        content: Text(
          'No se encontró un artículo con este código: $code. '
          'Puedes asignarlo a una variante existente y agregarla a la venta.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (ModalRoute.of(context)?.isCurrent == true) {
                Navigator.of(context).pop(false);
              }
            },
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (ModalRoute.of(context)?.isCurrent == true) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('Asignar a una variante existente'),
          ),
        ],
      ),
    );
    if (!context.mounted || !active() || accepted != true) return null;
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
