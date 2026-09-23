import 'package:flutter/material.dart';

import '../../../application/commands/ventas/actualizar_producto_borrador_command.dart';
import '../../../application/commands/ventas/eliminar_producto_borrador_command.dart';
import '../../../application/commands/ventas/venta_borrador_command_service.dart';
import '../../../application/sync/payloads/sale_item_snapshot.dart';
import '../../../core/di/injection.dart';
import '../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../domain/inventario/unidad_inventario.dart';
import '../../../domain/repositories/unidad_inventario_repository.dart';
import '../../../domain/ventas/sale_draft_item.dart';
import '../gestion_inventario/recursos/widgets/inventory_quantity_input_formatter.dart';
import 'models/sale_draft_display.dart';

/// Panel inferior para editar la cantidad de una línea del borrador o
/// eliminarla. Los cambios son temporales hasta pulsar «Actualizar artículo».
class DraftItemEditSheet extends StatefulWidget {
  const DraftItemEditSheet({
    required this.item,
    this.ventaBorradorCommandService,
    this.unidadInventarioRepository,
    super.key,
  });

  final SaleDraftItem item;
  final VentaBorradorCommandService? ventaBorradorCommandService;
  final UnidadInventarioRepository? unidadInventarioRepository;

  @override
  State<DraftItemEditSheet> createState() => _DraftItemEditSheetState();
}

class _DraftItemEditSheetState extends State<DraftItemEditSheet> {
  late final TextEditingController _controller;
  UnidadInventario? _unit;
  int? _parsed;
  String? _parseError;
  bool _saving = false;

  bool get _measured => widget.item.quantity == null;

  String get _name => [
    widget.item.productName,
    if (widget.item.variantName != null) widget.item.variantName!,
  ].join(' · ');

  /// Cantidad atómica o piezas capturadas al abrir el panel.
  int get _original => _measured
      ? widget.item.measuredQuantityAtomic!
      : widget.item.quantity!;

  /// Paso de los botones − / +. En ventas medidas es la cantidad de referencia
  /// que cubre el precio; por piezas, una unidad.
  int get _step => _measured ? widget.item.priceReferenceQuantityAtomic! : 1;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: SaleDraftDisplay.quantityNumber(widget.item),
    );
    _controller.addListener(_onTextChanged);
    _validateInput();
    if (_measured) _resolveUnit();
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(_validateInput);

  void _validateInput() {
    _parseError = null;
    if (_measured) {
      final unit = _unit;
      if (unit == null) {
        _parsed = null;
        _parseError = 'La unidad de venta no está disponible.';
        return;
      }
      try {
        _parsed = const InventoryQuantityCodec().parsePositiveAtomic(
          _controller.text,
          unit,
        );
      } on FormatException catch (error) {
        _parsed = null;
        _parseError = error.message as String? ?? 'Cantidad inválida.';
      }
      return;
    }
    final value = int.tryParse(_controller.text.trim());
    if (value == null || value <= 0) {
      _parsed = null;
      _parseError = 'Ingresa una cantidad mayor que cero.';
    } else if (value > SaleItemSnapshot.maxInteger) {
      _parsed = null;
      _parseError = 'La cantidad excede el límite permitido.';
    } else {
      _parsed = value;
    }
  }

  Future<void> _resolveUnit() async {
    final repository =
        widget.unidadInventarioRepository ??
        getIt<UnidadInventarioRepository>();
    final units = await repository.obtenerUnidadesActivas();
    if (!mounted) return;
    setState(() {
      for (final unit in units) {
        if (unit.code == widget.item.unitCode) {
          _unit = unit;
          break;
        }
      }
      _validateInput();
    });
  }

  bool get _dirty => _parsed != null && _parsed != _original;

  bool get _canUpdate => _dirty && !_saving;

  bool get _canDecrement {
    final parsed = _parsed;
    if (parsed == null) return false;
    return parsed - _step >= 0;
  }

  bool get _canIncrement {
    final parsed = _parsed;
    if (parsed == null) return false;
    return parsed + _step <= SaleItemSnapshot.maxInteger;
  }

  void _increment() {
    final parsed = _parsed;
    if (parsed == null) return;
    final result = parsed + _step;
    if (result > SaleItemSnapshot.maxInteger) return;
    _applyValue(result);
  }

  void _decrement() {
    final parsed = _parsed;
    if (parsed == null) return;
    final result = parsed - _step;
    if (result < 0) return;
    if (result == 0) {
      // Llegar a cero equivale a eliminar la línea.
      _askDelete();
      return;
    }
    _applyValue(result);
  }

  void _applyValue(int value) {
    _controller.text = _measured
        ? SaleDraftDisplay.measureNumber(value, widget.item.unitAtomicFactor!)
        : '$value';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    setState(_validateInput);
  }

  Future<void> _update() async {
    setState(() => _saving = true);
    try {
      await (widget.ventaBorradorCommandService ??
              getIt<VentaBorradorCommandService>())
          .actualizarProducto(
            ActualizarProductoBorradorCommand(
              saleItemId: widget.item.id,
              quantity: _measured ? null : _parsed,
              measuredQuantity: _measured ? _controller.text.trim() : null,
            ),
          );
      if (mounted) Navigator.of(context).pop();
    } on FormatException catch (error) {
      if (mounted) _message(error.message as String? ?? 'Cantidad inválida.');
    } on StateError catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) {
        _message('No se pudo actualizar el artículo. Intenta nuevamente.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _askDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar artículo?'),
        content: Text('$_name será eliminado de esta venta.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    // Cancelar conserva el artículo con la cantidad positiva que tenía.
    if (confirmed == true) await _delete();
  }

  Future<void> _delete() async {
    setState(() => _saving = true);
    try {
      await (widget.ventaBorradorCommandService ??
              getIt<VentaBorradorCommandService>())
          .eliminarProducto(
            EliminarProductoBorradorCommand(saleItemId: widget.item.id),
          );
      if (mounted) Navigator.of(context).pop();
    } on FormatException catch (error) {
      if (mounted) {
        _message(error.message as String? ?? 'No se pudo eliminar el artículo.');
      }
    } on StateError catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) {
        _message('No se pudo eliminar el artículo. Intenta nuevamente.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Editar $_name',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: _saving ? null : _askDelete,
                  tooltip: 'Eliminar artículo',
                  icon: const Icon(Icons.delete_outline),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Cerrar',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Expanded(child: Text('Precio de venta')),
                Text(
                  SaleDraftDisplay.price(widget.item),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Cantidad',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                IconButton(
                  onPressed: _saving || !_canDecrement ? null : _decrement,
                  tooltip: 'Disminuir cantidad',
                  icon: const Icon(Icons.remove),
                ),
                Expanded(
                  child: TextField(
                    key: const Key('draft_item_quantity_field'),
                    controller: _controller,
                    enabled: !_saving,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: _measured,
                      signed: false,
                    ),
                    inputFormatters: [
                      InventoryQuantityInputFormatter(
                        _measured ? _unit?.maximosDecimales ?? 9 : 0,
                      ),
                    ],
                    decoration: InputDecoration(
                      suffixText: _measured ? widget.item.unitSymbol : null,
                      errorText: _parseError,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _saving || !_canIncrement ? null : _increment,
                  tooltip: 'Aumentar cantidad',
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Aplicar oferta'),
              value: false,
              onChanged: null,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _canUpdate ? _update : null,
              child: Text(_saving ? 'Actualizando…' : 'Actualizar artículo'),
            ),
          ],
        ),
      ),
    );
  }
}