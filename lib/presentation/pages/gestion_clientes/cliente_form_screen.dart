import 'package:flutter/material.dart';
import 'cliente_form_result.dart';
import '../../../domain/clientes/cliente.dart';

class ClienteFormScreen extends StatefulWidget {
  const ClienteFormScreen({required this.onSave, this.cliente, super.key});
  final Cliente? cliente;
  final Future<void> Function(ClienteFormResult result) onSave;
  @override
  State<ClienteFormScreen> createState() => _ClienteFormScreenState();
}

class _ClienteFormScreenState extends State<ClienteFormScreen> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _telefono = TextEditingController();
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _nombre.text = widget.cliente?.nombre ?? '';
    _telefono.text = widget.cliente?.telefono ?? '';
  }

  @override
  void dispose() {
    _nombre.dispose();
    _telefono.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final phone = _telefono.text.trim();
      await widget.onSave(
        ClienteFormResult(
          nombre: _nombre.text.trim(),
          telefono: phone.isEmpty ? null : phone,
        ),
      );
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar el cliente. Inténtalo nuevamente.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.cliente == null ? 'Agregar cliente' : 'Editar cliente',
        ),
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
                          'DETALLES DEL CLIENTE',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('cliente_nombre'),
                          controller: _nombre,
                          enabled: !_saving,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.name],
                          decoration: const InputDecoration(
                            labelText: 'Nombre *',
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'El nombre es obligatorio.'
                              : null,
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          key: const Key('cliente_telefono'),
                          controller: _telefono,
                          enabled: !_saving,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          decoration: const InputDecoration(
                            labelText: 'Teléfono (opcional)',
                          ),
                          onFieldSubmitted: (_) => _save(),
                        ),
                        const SizedBox(height: 16),
                        if (widget.cliente != null)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: null,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Borrar'),
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
