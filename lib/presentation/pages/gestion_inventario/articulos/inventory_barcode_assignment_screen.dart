import 'package:flutter/material.dart';

import '../../../../application/commands/articulos/asignar_codigo_barras_variante_command.dart';
import '../../../../domain/articulos/articulo_detalle.dart';
import '../../../../domain/articulos/variante_detalle.dart';
import '../../../../domain/repositories/producto_repository.dart';
import '../../articulos/models/article_search_item.dart';

/// Carga solo el destino elegido y conserva su base hasta confirmar el guardado.
class InventoryBarcodeAssignmentScreen extends StatefulWidget {
  const InventoryBarcodeAssignmentScreen({
    required this.target,
    required this.code,
    required this.repository,
    required this.assign,
    super.key,
  });

  final ArticleSearchItem target;
  final String code;
  final ProductoRepository repository;
  final Future<void> Function(AsignarCodigoBarrasVarianteCommand) assign;

  @override
  State<InventoryBarcodeAssignmentScreen> createState() =>
      _InventoryBarcodeAssignmentScreenState();
}

class _InventoryBarcodeAssignmentScreenState
    extends State<InventoryBarcodeAssignmentScreen> {
  ArticuloDetalle? _detail;
  VarianteDetalle? _variant;
  bool _loading = true;
  bool _saving = false;
  bool _saved = false;
  String? _error;

  bool get _active => mounted && ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String? failedBase}) async {
    try {
      final detail = await widget.repository.obtenerDetalle(
        widget.target.article.productoId,
      );
      if (!_active) return;
      final variant = detail?.variantes
          .where((v) => v.id == widget.target.variant.varianteId)
          .firstOrNull;
      setState(() {
        _detail = detail;
        _variant = variant;
        _loading = false;
        if (variant == null || detail?.lastEventId == null) {
          _error =
              'El artículo o la variante ya no está disponible para asignar.';
        } else if (failedBase != null) {
          _error = detail!.lastEventId != failedBase
              ? 'El artículo cambió. Se recargaron sus datos. Revisa los códigos y confirma nuevamente.'
              : 'No se pudo guardar el código. Conservamos la selección; puedes reintentar.';
        } else {
          _error = null;
        }
      });
    } catch (_) {
      if (!_active) return;
      setState(() {
        _loading = false;
        // No permitir confirmar una base cuya vigencia no pudimos releer.
        _detail = null;
        _variant = null;
        _error =
            'No se pudo cargar el destino. Conservamos el código y la selección.';
      });
    }
  }

  Future<void> _save() async {
    final base = _detail?.lastEventId;
    if (_saving || _loading || base == null || _variant == null || !_active) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.assign(
        AsignarCodigoBarrasVarianteCommand(
          productId: widget.target.article.productoId,
          variantId: widget.target.variant.varianteId,
          baseEventId: base,
          codigoBarras: widget.code,
        ),
      );
    } catch (_) {
      // También cubre una carrera posterior a la lectura: el comando decide
      // atómicamente si la base sigue vigente; nunca reintenta automáticamente.
      await _load(failedBase: base);
      if (_active) setState(() => _saving = false);
      return;
    }
    if (!_active) return;
    setState(() => _saved = true);
    // Esperar la reconstrucción de PopScope antes de cerrar la ruta guardada.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_active) Navigator.of(context).pop('Código de barras guardado.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = _variant?.codigoBarras;
    final same = _variant != null && current == widget.code;
    final available = _variant != null && _detail?.lastEventId != null;
    final name = _variant == null
        ? widget.target.variant.nombre
        : _variant!.nombre;
    return PopScope<String>(
      canPop: _saved || !_saving,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: 'Cancelar',
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
          title: const Text('Confirmar código de barras'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _detail?.nombre ?? widget.target.article.nombre,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  name?.trim().isNotEmpty == true
                      ? name!
                      : 'Variante sin nombre',
                ),
                const SizedBox(height: 24),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (available) ...[
                  Text(
                    same
                        ? 'El código ya está asignado a esta variante.'
                        : current == null
                        ? '¿Asignar este código de barras?'
                        : '¿Reemplazar el código de barras?',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (current != null) Text('Código actual: $current'),
                ],
                Text('Código nuevo: ${widget.code}'),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    key: const Key('inventory_barcode_assignment_error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (_saving)
                  const Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        Text('Guardando…'),
                      ],
                    ),
                  )
                else if (!_loading && !available)
                  FilledButton(
                    onPressed: () {
                      setState(() => _loading = true);
                      _load();
                    },
                    child: const Text('Recargar destino'),
                  )
                else if (!_loading)
                  FilledButton(
                    key: const Key('inventory_barcode_confirm'),
                    onPressed: same
                        ? () => Navigator.of(
                            context,
                          ).pop('El código ya está asignado a esta variante.')
                        : _save,
                    child: Text(
                      same
                          ? 'Volver al inventario'
                          : current == null
                          ? 'Asignar código'
                          : 'Reemplazar código',
                    ),
                  ),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
