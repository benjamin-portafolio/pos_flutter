import 'package:flutter/material.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;
import 'package:uuid/uuid.dart';

import '../../../../domain/finanzas/financial_direction.dart';
import '../../../../domain/finanzas/financial_nature.dart';
import '../models/categoria_financiera_form_result.dart';

/// Alta de una categoría financiera: nombre + clasificación sencilla
/// (naturaleza). La dirección se deriva del botón que abrió el formulario y no
/// es editable aquí. Guarda por el command service real inyectado en `onSave`;
/// el `categoryId` se genera una sola vez por intención para que reintentar la
/// misma captura reutilice la misma identidad (idempotencia del command).
class CategoriaFinancieraFormScreen extends StatefulWidget {
  const CategoriaFinancieraFormScreen({
    super.key,
    required this.direction,
    required this.onSave,
  });

  final FinancialDirection direction;
  final Future<void> Function(CategoriaFinancieraFormResult result) onSave;

  @override
  State<CategoriaFinancieraFormScreen> createState() =>
      _CategoriaFinancieraFormScreenState();
}

class _CategoriaFinancieraFormScreenState
    extends State<CategoriaFinancieraFormScreen> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  late final String _categoryId = const Uuid().v4();
  late FinancialNature _nature = FinancialNature.operating;
  bool _saving = false;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  List<FinancialNature> get _natures => FinancialNature.values
      .where((n) => !(widget.direction == FinancialDirection.income && n.onlyOut))
      .toList();

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await widget.onSave(
        CategoriaFinancieraFormResult(
          categoryId: _categoryId,
          name: unorm.nfkc(_nombre.text).trim(),
          direction: widget.direction,
          nature: _nature,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        CategoriaFinancieraFormResult(
          categoryId: _categoryId,
          name: unorm.nfkc(_nombre.text).trim(),
          direction: widget.direction,
          nature: _nature,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo guardar la categoría. Inténtalo nuevamente.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final widgetDirectionLabel = widget.direction.label;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Nueva categoría ($widgetDirectionLabel)'),
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
                            'DETALLES DE LA CATEGORÍA',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const Key('categoria_nombre'),
                            controller: _nombre,
                            enabled: !_saving,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: 'Nombre *',
                            ),
                            validator: (v) {
                              final normalized = unorm.nfkc(v ?? '').trim();
                              if (normalized.isEmpty) {
                                return 'El nombre de la categoría financiera es obligatorio.';
                              }
                              if (normalized.runes.length > 100) {
                                return 'name debe tener entre 1 y 100 caracteres.';
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => _save(),
                          ),
                          const SizedBox(height: 24),
                          DropdownButtonFormField<FinancialNature>(
                            key: const Key('categoria_naturaleza'),
                            initialValue: _nature,
                            decoration: const InputDecoration(labelText: 'Clasificación'),
                            items: [
                              for (final n in _natures)
                                DropdownMenuItem(
                                  value: n,
                                  child: Text(n.label),
                                ),
                            ],
                            onChanged: _saving
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() => _nature = value);
                                    }
                                  },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'La clasificación es inmutable desde el alta y no se '
                            'infiere del nombre.',
                            style: Theme.of(context).textTheme.bodySmall,
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