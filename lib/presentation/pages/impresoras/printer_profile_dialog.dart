import 'package:flutter/material.dart';

import '../../../application/printing/printer_device.dart';
import '../../../application/printing/printer_profile.dart';

class PrinterProfileDialog extends StatefulWidget {
  const PrinterProfileDialog({super.key, required this.device, this.profile});

  final PrinterDevice device;
  final PrinterProfile? profile;

  @override
  State<PrinterProfileDialog> createState() => _PrinterProfileDialogState();
}

class _PrinterProfileDialogState extends State<PrinterProfileDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _alias;
  late PrinterPaper _paper;
  late final TextEditingController _width;
  late PrinterImageCommand _imageCommand;
  late bool _supportsCut;

  @override
  void initState() {
    super.initState();
    _alias = TextEditingController(
      text: widget.profile?.alias ?? widget.device.name ?? 'Impresora',
    );
    _paper = widget.profile?.paper ?? PrinterPaper.mm58;
    _width = TextEditingController(
      text: '${widget.profile?.printableWidthDots ?? 384}',
    );
    _imageCommand = widget.profile?.imageCommand ?? PrinterImageCommand.gsV0;
    _supportsCut = widget.profile?.supportsCut ?? false;
  }

  @override
  void dispose() {
    _alias.dispose();
    _width.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.profile == null ? 'Guardar impresora' : 'Editar impresora',
    ),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.device.address),
            const SizedBox(height: 16),
            TextFormField(
              controller: _alias,
              decoration: const InputDecoration(labelText: 'Alias'),
              maxLength: 80,
              validator: (value) =>
                  (value?.trim().isEmpty ?? true) ? 'Escribe un alias.' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PrinterPaper>(
              initialValue: _paper,
              decoration: const InputDecoration(labelText: 'Papel'),
              items: const [
                DropdownMenuItem(
                  value: PrinterPaper.mm58,
                  child: Text('58 mm'),
                ),
                DropdownMenuItem(
                  value: PrinterPaper.mm80,
                  child: Text('80 mm'),
                ),
              ],
              onChanged: (value) => setState(() {
                _paper = value!;
                _width.text = value == PrinterPaper.mm58 ? '384' : '576';
              }),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _width,
              decoration: const InputDecoration(
                labelText: 'Ancho imprimible (puntos)',
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                final width = int.tryParse(value ?? '');
                return width == null ||
                        width < 8 ||
                        width > 2048 ||
                        width % 8 != 0
                    ? 'Usa un múltiplo de 8 entre 8 y 2048.'
                    : null;
              },
            ),
            DropdownButtonFormField<PrinterImageCommand>(
              initialValue: _imageCommand,
              decoration: const InputDecoration(labelText: 'Comando de imagen'),
              items: [
                for (final command in PrinterImageCommand.values)
                  DropdownMenuItem(value: command, child: Text(command.name)),
              ],
              onChanged: (value) => setState(() => _imageCommand = value!),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enviar comando de corte'),
              value: _supportsCut,
              onChanged: (value) => setState(() => _supportsCut = value),
            ),
            const SizedBox(height: 16),
            const Text('Ajusta imágenes y corte mediante pruebas físicas.'),
            const Text(
              'El papel seleccionado requiere verificación con el equipo físico.',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Guardar')),
    ],
  );

  void _submit() {
    if (!_form.currentState!.validate()) return;
    try {
      final profile = PrinterProfile(
        address: widget.device.address,
        transport: widget.device.transport,
        alias: _alias.text,
        paper: _paper,
        printableWidthDots: int.parse(_width.text),
        imageCommand: _imageCommand,
        supportsCut: _supportsCut,
      );
      Navigator.of(context).pop(profile);
    } on ArgumentError {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El perfil de impresora no es válido.')),
      );
    }
  }
}
