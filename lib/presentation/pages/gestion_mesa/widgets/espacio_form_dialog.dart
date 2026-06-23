import 'package:flutter/material.dart';

import '../../../../domain/espacios/visibilidad_espacio.dart';
import '../../../widgets/dialogs/labeled_underline_field.dart';
import '../../../widgets/dialogs/management_dialog_header.dart';
import '../models/espacio_form_result.dart';

class EspacioFormDialog extends StatefulWidget {
  const EspacioFormDialog({super.key});

  @override
  State<EspacioFormDialog> createState() => _EspacioFormDialogState();
}

class _EspacioFormDialogState extends State<EspacioFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _tituloController = TextEditingController();
  final _identificacionController = TextEditingController();
  VisibilidadEspacio _visibilidad = VisibilidadEspacio.sinRestriccion;

  @override
  void dispose() {
    _tituloController.dispose();
    _identificacionController.dispose();
    super.dispose();
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      EspacioFormResult(
        titulo: _tituloController.text.trim(),
        identificacion: _identificacionController.text.trim(),
        visibilidad: _visibilidad,
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
                titulo: 'ADMINISTRACIÓN DEL ESPACIO',
                textoBoton: 'AGREGAR NUEVO ESPACIO',
                onConfirmar: _guardar,
              ),
              const SizedBox(height: 12),
              LabeledUnderlineField(
                label: 'Título del espacio',
                hint: 'Ejemplo: 1er piso',
                controller: _tituloController,
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Ingresa un título'
                    : null,
              ),
              const SizedBox(height: 8),
              LabeledUnderlineField(
                label: 'Identificación única',
                hint: 'Ejemplo: piso_1',
                controller: _identificacionController,
              ),
              const SizedBox(height: 12),
              Card(
                shape: const RoundedRectangleBorder(),
                child: RadioGroup<VisibilidadEspacio>(
                  groupValue: _visibilidad,
                  onChanged: (value) => setState(() => _visibilidad = value!),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<VisibilidadEspacio>(
                        value: VisibilidadEspacio.sinRestriccion,
                        title: const Text(
                          'Mostrar artículos sin restricción junto con '
                          'los artículos restringidos a este espacio',
                        ),
                      ),
                      RadioListTile<VisibilidadEspacio>(
                        value: VisibilidadEspacio.soloRestringido,
                        title: const Text(
                          'Mostrar solo los artículos restringidos a este '
                          'espacio',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
