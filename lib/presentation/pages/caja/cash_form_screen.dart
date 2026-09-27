import 'package:flutter/material.dart';
import 'cash_money.dart';

/// Formulario conserva valores ante errores y solo confirma tras commit.
class CashFormScreen extends StatefulWidget {
  const CashFormScreen({super.key, required this.onSave, this.expectedMinor});
  final Future<void> Function(int amount, String? notes) onSave;
  final BigInt? expectedMinor;
  @override
  State<CashFormScreen> createState() => _CashFormScreenState();
}

class _CashFormScreenState extends State<CashFormScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController(), _notes = TextEditingController();
  bool _saving = false;
  bool get closing => widget.expectedMinor != null;
  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(parseCashMoney(_amount.text)!, _notes.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError
                  ? error.message
                  : 'No se pudo guardar: $error',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final counted = parseCashMoney(_amount.text);
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: Text(closing ? 'Corte de caja' : 'Abrir caja')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 650),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          closing
                              ? 'Cuenta el efectivo que queda en el cajón.'
                              : 'Captura el fondo inicial de esta terminal.',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 24),
                        if (closing) ...[
                          Text(
                            'Efectivo esperado: ${cashMoney(widget.expectedMinor!)}',
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          key: const Key('cash_amount'),
                          controller: _amount,
                          enabled: !_saving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: closing
                                ? 'Efectivo contado (MXN)'
                                : 'Fondo inicial (MXN)',
                            hintText: '0.00',
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: (v) => parseCashMoney(v ?? '') == null
                              ? 'Captura un importe válido, desde cero.'
                              : null,
                        ),
                        if (closing) ...[
                          const SizedBox(height: 20),
                          Text(
                            'Diferencia: ${counted == null ? '—' : cashMoney(BigInt.from(counted) - widget.expectedMinor!)}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            key: const Key('cash_notes'),
                            controller: _notes,
                            enabled: !_saving,
                            maxLength: 500,
                            decoration: const InputDecoration(
                              labelText: 'Nota (opcional)',
                            ),
                          ),
                          const Text(
                            'El corte es definitivo en esta terminal. Su aceptación central puede quedar pendiente.',
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          key: const Key('cash_save'),
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  closing ? Icons.lock : Icons.point_of_sale,
                                ),
                          label: Text(
                            _saving
                                ? 'Guardando…'
                                : closing
                                ? 'Cerrar caja'
                                : 'Abrir caja',
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
    );
  }
}
