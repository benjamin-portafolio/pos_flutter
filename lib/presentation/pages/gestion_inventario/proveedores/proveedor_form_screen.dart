import 'package:flutter/material.dart';
import '../../../../application/config/app_config.dart';
import '../../../../application/config/app_config_controller.dart';
import '../../../../domain/proveedores/proveedor.dart';
import 'models/proveedor_form_result.dart';

class ProveedorFormScreen extends StatefulWidget {
  const ProveedorFormScreen({
    required this.onSave,
    required this.config,
    this.proveedor,
    super.key,
  });
  final Proveedor? proveedor;
  final AppConfigController config;
  final Future<void> Function(ProveedorFormResult result) onSave;

  @override
  State<ProveedorFormScreen> createState() => _ProveedorFormScreenState();
}

class _ProveedorFormScreenState extends State<ProveedorFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(
    text: widget.proveedor?.nombre ?? '',
  );
  late final _telefono = TextEditingController(
    text: widget.proveedor?.telefono ?? '',
  );
  late final _notas = TextEditingController(
    text: widget.proveedor?.notas ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _nombre.dispose();
    _telefono.dispose();
    _notas.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await widget.onSave(
        ProveedorFormResult(
          nombre: _nombre.text.trim(),
          telefono: _optional(_telefono.text),
          notas: _optional(_notas.text),
        ),
      );
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StateError
                ? error.message.toString()
                : 'No se pudo guardar el proveedor. Inténtalo nuevamente.',
          ),
        ),
      );
    }
  }

  String? _optional(String value) => value.trim().isEmpty ? null : value.trim();

  @override
  Widget build(BuildContext context) => StreamBuilder<AppConfig>(
    stream: widget.config.changes,
    initialData: widget.config.config,
    builder: (context, snapshot) {
      final available = snapshot.hasData;
      return PopScope(
        canPop: !_saving,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              widget.proveedor == null
                  ? 'Añadir proveedor'
                  : 'Editar proveedor',
            ),
            leading: IconButton(
              key: const Key('cancel_supplier_button'),
              tooltip: 'Cancelar',
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ),
          body: SafeArea(
            child: available
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Form(
                              key: _form,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'DETALLES DEL PROVEEDOR',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 24),
                                  TextFormField(
                                    key: const Key('supplier_name_field'),
                                    controller: _nombre,
                                    enabled: !_saving,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: 'Nombre *',
                                    ),
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                        ? 'El nombre es obligatorio.'
                                        : null,
                                  ),
                                  const SizedBox(height: 24),
                                  TextFormField(
                                    key: const Key('supplier_phone_field'),
                                    controller: _telefono,
                                    enabled: !_saving,
                                    keyboardType: TextInputType.phone,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: 'Teléfono (opcional)',
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  TextFormField(
                                    key: const Key('supplier_notes_field'),
                                    controller: _notas,
                                    enabled: !_saving,
                                    keyboardType: TextInputType.multiline,
                                    minLines: 3,
                                    maxLines: 6,
                                    decoration: const InputDecoration(
                                      labelText: 'Notas (opcional)',
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  FilledButton.icon(
                                    key: const Key('save_supplier_button'),
                                    onPressed: _saving ? null : _save,
                                    icon: _saving
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.check),
                                    label: Text(
                                      _saving ? 'Guardando…' : 'Guardar',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : const Center(
                    child: Text(
                      'No se pudo cargar la configuración.',
                    ),
                  ),
          ),
        ),
      );
    },
  );
}
