import 'package:flutter/material.dart';

import '../../../../application/commands/articulos/asignar_codigo_barras_variante_command.dart';
import '../../../../domain/articulos/codigo_barras.dart';
import '../../../../domain/articulos/variante_por_codigo_barras.dart';
import '../../../../domain/repositories/producto_repository.dart';
import '../../articulos/models/article_search_item.dart';
import 'inventory_barcode_assignment_screen.dart';
import 'unknown_barcode_dialog.dart';
import 'inventory_barcode_matches_dialog.dart';
import 'inventory_barcode_variant_selector.dart';
import 'widgets/barcode_scanner_screen.dart';

/// La ruta delimita la vida de las consultas y de la navegación del escaneo.
class InventoryBarcodeFlowScreen extends StatefulWidget {
  const InventoryBarcodeFlowScreen({
    required this.repository,
    required this.assign,
    required this.openArticle,
    required this.createArticle,
    super.key,
  });

  final Future<void> Function(BuildContext, String code) createArticle;
  final ProductoRepository repository;
  final Future<void> Function(AsignarCodigoBarrasVarianteCommand) assign;
  final Future<bool> Function(BuildContext, String productId, String variantId)
  openArticle;

  @override
  State<InventoryBarcodeFlowScreen> createState() =>
      _InventoryBarcodeFlowScreenState();
}

class _InventoryBarcodeFlowScreenState
    extends State<InventoryBarcodeFlowScreen> {
  String? _code;
  String? _error;
  bool _busy = true;

  bool get _active => mounted && ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    if (!mounted || !_active) return;
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (!mounted || !_active) return;
    if (raw == null) {
      Navigator.of(context).pop();
      return;
    }
    try {
      _code = CodigoBarras.fromInput(raw).value;
      if (_code == null) throw ArgumentError('El código está vacío.');
    } on ArgumentError catch (error) {
      setState(() {
        _busy = false;
        _error = error.message?.toString() ?? 'Código de barras inválido.';
      });
      return;
    }
    await _lookup();
  }

  Future<void> _lookup() async {
    if (!mounted || !_active) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final matches = await widget.repository.buscarVariantesPorCodigoBarras(
        _code!,
      );
      if (!mounted || !_active) return;
      setState(() => _busy = false);
      if (matches.isEmpty) {
        await _offerAssignment();
        return;
      }
      final match = matches.length == 1
          ? matches.single
          : await showDialog<VariantePorCodigoBarras>(
              context: context,
              builder: (_) => InventoryBarcodeMatchesDialog(matches: matches),
            );
      if (!mounted || !_active) return;
      if (match == null) {
        Navigator.of(context).pop();
        return;
      }
      setState(() => _busy = true);
      final opened = await widget.openArticle(
        context,
        match.productoId,
        match.varianteId,
      );
      if (!mounted || !_active) return;
      if (opened) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _busy = false;
          _error =
              'No se pudo abrir la variante. Vuelve a consultar el código.';
        });
      }
    } catch (_) {
      if (!mounted || !_active) return;
      setState(() {
        _busy = false;
        _error = 'No se pudo consultar el código. Intenta nuevamente.';
      });
    }
  }

  Future<void> _offerAssignment() async {
    final action = await showDialog<UnknownBarcodeAction>(
      context: context,
      builder: (_) => UnknownBarcodeDialog(code: _code!),
    );
    if (!mounted || !_active) return;
    if (action == UnknownBarcodeAction.create) {
      await widget.createArticle(context, _code!);
      if (mounted && _active) Navigator.of(context).pop();
      return;
    }
    if (action != UnknownBarcodeAction.assign) {
      Navigator.of(context).pop();
      return;
    }
    final target = await Navigator.of(context).push<ArticleSearchItem>(
      MaterialPageRoute(
        builder: (_) => InventoryBarcodeVariantSelector(
          repository: widget.repository,
          code: _code!,
        ),
      ),
    );
    if (!mounted || !_active) return;
    if (target == null) {
      Navigator.of(context).pop();
      return;
    }
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => InventoryBarcodeAssignmentScreen(
          target: target,
          code: _code!,
          repository: widget.repository,
          assign: widget.assign,
        ),
      ),
    );
    if (mounted && _active) Navigator.of(context).pop(message);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Código de barras')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _busy
            ? const CircularProgressIndicator()
            : _error == null
            ? Text('Código: $_code')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_code != null) Text('Código: $_code'),
                  Text(_error!),
                  FilledButton(
                    onPressed: () {
                      if (_busy) return;
                      setState(() => _busy = true);
                      _code == null ? _scan() : _lookup();
                    },
                    child: Text(
                      _code == null ? 'Volver a escanear' : 'Reintentar',
                    ),
                  ),
                ],
              ),
      ),
    ),
  );
}
