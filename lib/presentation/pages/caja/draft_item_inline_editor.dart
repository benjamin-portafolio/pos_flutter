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

/// Controles de cantidad y eliminación dentro de la línea seleccionada.
class DraftItemInlineEditor extends StatefulWidget {
  const DraftItemInlineEditor({
    required this.item,
    required this.onClose,
    required this.onSavingChanged,
    this.enabled = true,
    this.ventaBorradorCommandService,
    this.unidadInventarioRepository,
    super.key,
  });

  final SaleDraftItem item;
  final VoidCallback onClose;
  final ValueChanged<bool> onSavingChanged;
  final bool enabled;
  final VentaBorradorCommandService? ventaBorradorCommandService;
  final UnidadInventarioRepository? unidadInventarioRepository;

  @override
  State<DraftItemInlineEditor> createState() => _DraftItemInlineEditorState();
}

class _DraftItemInlineEditorState extends State<DraftItemInlineEditor> {
  late final TextEditingController _controller;
  UnidadInventario? _unit;
  int? _parsed;
  String? _parseError;
  bool _saving = false;
  bool _confirmDelete = false;
  late int _committed;

  bool get _measured => widget.item.quantity == null;

  /// Cantidad atómica o piezas persistidas de la línea.
  int get _original =>
      _measured ? widget.item.measuredQuantityAtomic! : widget.item.quantity!;

  /// Paso de los botones − / +. En ventas medidas es la cantidad de referencia
  /// que cubre el precio; por piezas, una unidad.
  int get _step => _measured ? widget.item.priceReferenceQuantityAtomic! : 1;

  @override
  void initState() {
    super.initState();
    _committed = _original;
    _controller = TextEditingController(
      text: SaleDraftDisplay.quantityNumber(widget.item),
    );
    _controller.addListener(_onTextChanged);
    _validateInput();
    if (_measured) _resolveUnit();
  }

  @override
  void didUpdateWidget(covariant DraftItemInlineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous =
        oldWidget.item.quantity ?? oldWidget.item.measuredQuantityAtomic;
    if (previous != _original) {
      _committed = _original;
      _controller.text = SaleDraftDisplay.quantityNumber(widget.item);
      _validateInput();
    }
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
    final List<UnidadInventario> units;
    try {
      units = await repository.obtenerUnidadesActivas();
    } catch (_) {
      if (mounted) setState(_validateInput);
      return;
    }
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

  bool get _dirty => _parsed != null && _parsed != _committed;

  bool get _canUpdate => _dirty && !_saving && widget.enabled;

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
    if (_saving || !widget.enabled) return;
    final parsed = _parsed;
    if (parsed == null) return;
    final result = parsed + _step;
    if (result > SaleItemSnapshot.maxInteger) return;
    _applyValue(result);
    _update();
  }

  void _decrement() {
    if (_saving || !widget.enabled) return;
    final parsed = _parsed;
    if (parsed == null) return;
    final result = parsed - _step;
    if (result < 0) return;
    if (result == 0) {
      // Llegar a cero equivale a eliminar la línea.
      setState(() => _confirmDelete = true);
      return;
    }
    _applyValue(result);
    _update();
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
    if (!_canUpdate) return;
    final value = _parsed!;
    setState(() => _saving = true);
    widget.onSavingChanged(true);
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
      if (mounted) _committed = value;
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
      widget.onSavingChanged(false);
    }
  }

  Future<void> _delete() async {
    if (_saving || !widget.enabled) return;
    var deleted = false;
    setState(() => _saving = true);
    widget.onSavingChanged(true);
    try {
      await (widget.ventaBorradorCommandService ??
              getIt<VentaBorradorCommandService>())
          .eliminarProducto(
            EliminarProductoBorradorCommand(saleItemId: widget.item.id),
          );
      deleted = true;
    } on FormatException catch (error) {
      if (mounted) {
        _message(
          error.message as String? ?? 'No se pudo eliminar el artículo.',
        );
      }
    } on StateError catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) {
        _message('No se pudo eliminar el artículo. Intenta nuevamente.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
      widget.onSavingChanged(false);
      if (deleted) widget.onClose();
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && !_saving;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              onPressed: enabled && _canDecrement ? _decrement : null,
              tooltip: 'Disminuir cantidad',
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: TextField(
                key: const Key('draft_item_quantity_field'),
                controller: _controller,
                enabled: enabled,
                textAlign: TextAlign.center,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _update(),
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
                  labelText: 'Cantidad',
                  suffixText: _measured ? widget.item.unitSymbol : null,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            IconButton(
              onPressed: enabled && _canIncrement ? _increment : null,
              tooltip: 'Aumentar cantidad',
              icon: const Icon(Icons.add),
            ),
            IconButton(
              onPressed: enabled
                  ? () => setState(() => _confirmDelete = !_confirmDelete)
                  : null,
              tooltip: 'Eliminar artículo',
              color: Theme.of(context).colorScheme.error,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        if (_dirty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _canUpdate ? _update : null,
              icon: const Icon(Icons.check),
              label: const Text('Aplicar cantidad'),
            ),
          ),
        if (_parseError != null)
          Text(
            _parseError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_confirmDelete)
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              const Text('¿Eliminar artículo?'),
              TextButton(
                onPressed: enabled
                    ? () => setState(() => _confirmDelete = false)
                    : null,
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: enabled ? _delete : null,
                child: const Text('Eliminar'),
              ),
            ],
          ),
      ],
    );
  }
}
