import 'package:flutter/material.dart';

import '../../../widgets/dialogs/labeled_underline_field.dart';
import '../../../widgets/dialogs/management_dialog_header.dart';
import '../models/mesa_form_result.dart';

class MesaFormDialog extends StatefulWidget {
  const MesaFormDialog({super.key, required this.espaciosDisponibles});

  final List<String> espaciosDisponibles;

  @override
  State<MesaFormDialog> createState() => _MesaFormDialogState();
}

class _MesaFormDialogState extends State<MesaFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _capacidadController = TextEditingController();
  late String _espacioSeleccionado = widget.espaciosDisponibles.first;
  EstadoMesa _estado = EstadoMesa.libre;

  @override
  void dispose() {
    _nombreController.dispose();
    _capacidadController.dispose();
    super.dispose();
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      MesaFormResult(
        nombre: _nombreController.text.trim(),
        capacidad: int.parse(_capacidadController.text.trim()),
        espacio: _espacioSeleccionado,
        estado: _estado,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: const RoundedRectangleBorder(),
      insetPadding: EdgeInsets.only(
        top: kToolbarHeight + MediaQuery.of(context).padding.top,
      ),
      child: Form(
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ManagementDialogHeader(
                titulo: 'ADMINISTRACIÓN DE LA MESA',
                textoBoton: 'AGREGAR NUEVA MESA',
                onConfirmar: _guardar,
              ),
              const SizedBox(height: 12),
              LabeledUnderlineField(
                label: 'Nombre de la mesa',
                hint: 'Ejemplo: Mesa 9',
                controller: _nombreController,
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Ingresa un nombre'
                    : null,
              ),
              const SizedBox(height: 8),
              LabeledUnderlineField(
                label: 'Capacidad',
                hint: 'Ejemplo: 4',
                controller: _capacidadController,
                keyboardType: TextInputType.number,
                validator: (value) {
                  final numero = int.tryParse(value ?? '');
                  return (numero == null || numero <= 0)
                      ? 'Ingresa una capacidad válida'
                      : null;
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _espacioSeleccionado,
                decoration: const InputDecoration(labelText: 'Espacio'),
                items: widget.espaciosDisponibles
                    .map(
                      (espacio) => DropdownMenuItem(
                        value: espacio,
                        child: Text(espacio),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _espacioSeleccionado = value!),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<EstadoMesa>(
                initialValue: _estado,
                decoration: const InputDecoration(labelText: 'Estado'),
                items: const [
                  DropdownMenuItem(
                    value: EstadoMesa.libre,
                    child: Text('Libre'),
                  ),
                  DropdownMenuItem(
                    value: EstadoMesa.ocupado,
                    child: Text('Ocupado'),
                  ),
                  DropdownMenuItem(
                    value: EstadoMesa.reservado,
                    child: Text('Reservado'),
                  ),
                ],
                onChanged: (value) => setState(() => _estado = value!),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
