import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../domain/finanzas/financial_category.dart';
import '../models/money_input.dart';
import '../models/movimiento_financiero_form_result.dart';

/// Registro de un ingreso/gasto adicional: categoría (pre-seleccionada),
/// importe, fecha efectiva, método cash/transfer, nota y referencia
/// opcionales. Guarda por el command service real inyectado en `onSave`.
///
/// `entryId` se genera una sola vez por intención: reintentar la misma captura
/// (por ejemplo tras un fallo de escritura) reutiliza la misma identidad y el
/// command service la resuelve de forma idempotente, sin duplicar dinero.
class MovimientoFinancieroFormScreen extends StatefulWidget {
  const MovimientoFinancieroFormScreen({
    super.key,
    required this.category,
    required this.onSave,
    this.now,
    this.cashEnabled = false,
  });

  final bool cashEnabled;
  final FinancialCategory category;
  final Future<void> Function(MovimientoFinancieroFormResult result) onSave;

  /// Proveedor de «ahora» para pruebas y para la fecha efectiva por defecto.
  final DateTime Function()? now;

  @override
  State<MovimientoFinancieroFormScreen> createState() =>
      _MovimientoFinancieroFormScreenState();
}

class _MovimientoFinancieroFormScreenState
    extends State<MovimientoFinancieroFormScreen> {
  final _form = GlobalKey<FormState>();
  final _importe = TextEditingController();
  final _nota = TextEditingController();
  final _referencia = TextEditingController();
  late final String _entryId = const Uuid().v4();
  late String _method = 'cash';
  late DateTime _fecha = _now();
  bool _saving = false;
  bool _affectsDrawer = false;

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  /// Fecha/hora efectiva en hora local del dispositivo, para la etiqueta del
  /// botón. El valor persistido es `_fecha.toUtc().millisecondsSinceEpoch`.
  String _fechaLocal(DateTime fecha) {
    final hh = fecha.hour.toString().padLeft(2, '0');
    final mm = fecha.minute.toString().padLeft(2, '0');
    return '${fecha.day}/${fecha.month}/${fecha.year} $hh:$mm';
  }

  @override
  void dispose() {
    _importe.dispose();
    _nota.dispose();
    _referencia.dispose();
    super.dispose();
  }

  Future<void> _pickFecha() async {
    if (_saving) return;
    final now = _now();
    final date = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2000),
      lastDate: now,
      helpText: 'Fecha efectiva del registro',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_fecha),
      helpText: 'Hora efectiva',
    );
    if (time == null || !mounted) return;
    setState(() {
      _fecha = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  static const _maxFutureToleranceMs = 5 * 60 * 1000;

  /// Tolerancia de reloj del command (contrato §2.4): `occurred_at_ms` mayor
  /// que `now + 5 min` es inválido en la captura local.
  bool _esFutura(DateTime fecha) =>
      fecha.toUtc().millisecondsSinceEpoch >
      _now().toUtc().millisecondsSinceEpoch + _maxFutureToleranceMs;

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final minor = MoneyInput.parseMinor(_importe.text);
    if (minor == null) return;
    if (_esFutura(_fecha)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La fecha del registro no puede ser futura.'),
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final notes = _nota.text.trim();
    final reference = _referencia.text.trim();
    try {
      await widget.onSave(
        MovimientoFinancieroFormResult(
          affectsDrawer: _affectsDrawer,
          entryId: _entryId,
          categoryId: widget.category.id,
          amountMinor: minor,
          method: _method,
          occurredAtMs: _fecha.toUtc().millisecondsSinceEpoch,
          notes: notes.isEmpty ? null : notes,
          reference: reference.isEmpty ? null : reference,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StateError
                ? error.message
                : 'No se pudo guardar el registro. Inténtalo nuevamente.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = widget.category;
    final title = category.direction.label;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Registrar ${title.toLowerCase()}'),
          leading: IconButton(
            tooltip: 'Cancelar',
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
          actions: [
            TextButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle),
              label: Text(_saving ? 'Guardando…' : 'Guardar'),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            category.name,
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${category.direction.label} · ${category.nature.label}',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const Key('movimiento_importe'),
                            controller: _importe,
                            enabled: !_saving,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Importe (MXN) *',
                              hintText: '0.00',
                              prefixText: '\$ ',
                            ),
                            validator: (v) {
                              final minor = MoneyInput.parseMinor(v ?? '');
                              if (minor == null) {
                                return 'El importe debe ser un entero positivo en centavos.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  'Fecha efectiva',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                              OutlinedButton.icon(
                                key: const Key('movimiento_fecha'),
                                onPressed: _saving ? null : _pickFecha,
                                icon: const Icon(Icons.calendar_month),
                                label: Text(_fechaLocal(_fecha)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          DropdownButtonFormField<String>(
                            key: const Key('movimiento_method'),
                            initialValue: _method,
                            decoration: const InputDecoration(
                              labelText: 'Método',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'cash',
                                child: Text('Efectivo'),
                              ),
                              DropdownMenuItem(
                                value: 'transfer',
                                child: Text('Transferencia'),
                              ),
                            ],
                            onChanged: _saving
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() {
                                        _method = value;
                                        if (value != 'cash') {
                                          _affectsDrawer = false;
                                        }
                                      });
                                    }
                                  },
                          ),
                          if (widget.cashEnabled && _method == 'cash')
                            SwitchListTile(
                              key: const Key('financial_affects_drawer'),
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                category.direction.code == 'in'
                                    ? 'Este efectivo entra a la caja'
                                    : 'Este efectivo sale de la caja',
                              ),
                              subtitle: const Text(
                                'Si lo activas, se requiere una caja abierta en esta terminal.',
                              ),
                              value: _affectsDrawer,
                              onChanged: _saving
                                  ? null
                                  : (v) => setState(() => _affectsDrawer = v),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            'La transferencia no entra a ninguna caja ni suma al '
                            'corte. Se refleja en el saldo de la cuenta, que se '
                            'declara por separado.',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            key: const Key('movimiento_nota'),
                            controller: _nota,
                            enabled: !_saving,
                            maxLength: 500,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              labelText: 'Nota (opcional)',
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            key: const Key('movimiento_referencia'),
                            controller: _referencia,
                            enabled: !_saving,
                            maxLength: 500,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              labelText: 'Referencia (opcional)',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
