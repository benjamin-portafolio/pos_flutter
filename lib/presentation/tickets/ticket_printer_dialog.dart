import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/printing/printer_profile.dart';
import '../../application/printing/printer_settings.dart';
import '../../application/printing/printer_settings_controller.dart';
import '../../application/tickets/ticket_document.dart';

/// A destination for this send only. Never writes the installation default.
class TicketPrinterDialog extends StatefulWidget {
  const TicketPrinterDialog({
    required this.controller,
    required this.currentDocument,
    super.key,
  });
  final PrinterSettingsController controller;
  final TicketDocument? Function() currentDocument;

  @override
  State<TicketPrinterDialog> createState() => _TicketPrinterDialogState();
}

class _TicketPrinterDialogState extends State<TicketPrinterDialog> {
  late final StreamSubscription<PrinterSettings> _changes;
  String? _address;
  bool _choosing = false;

  @override
  void initState() {
    super.initState();
    _address = widget.controller.settings.defaultAddress;
    _choosing = _address == null;
    _changes = widget.controller.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _changes.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.controller.settings;
    final selected = settings.printers
        .where((p) => p.address == _address)
        .firstOrNull;
    return AlertDialog(
      title: const Text('Imprimir ticket'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selected != null) ...[
                Text('Destino: ${selected.alias}'),
                Text(
                  '${selected.address} · ${selected.paper == PrinterPaper.mm58 ? 58 : 80} mm',
                ),
                Text(
                  selected.address == settings.defaultAddress
                      ? 'Predeterminada'
                      : 'Solo para este envío',
                ),
              ],
              if (_choosing || selected == null)
                for (final profile in settings.printers)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(profile.alias),
                    subtitle: Text(
                      '${profile.address} · ${profile.paper == PrinterPaper.mm58 ? 58 : 80} mm'
                      '${profile.address == settings.defaultAddress ? ' · Predeterminada' : ''}',
                    ),
                    selected: profile.address == _address,
                    onTap: () => setState(() {
                      _address = profile.address;
                      _choosing = false;
                    }),
                  ),
              if (selected != null && !_choosing)
                TextButton(
                  onPressed: () => setState(() => _choosing = true),
                  child: const Text('Cambiar impresora'),
                ),
              if (settings.printers.isEmpty)
                const Text('No hay impresoras guardadas.'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: selected == null
              ? null
              : () {
                  final document = widget.currentDocument();
                  if (document == null) {
                    Navigator.pop(context);
                    return;
                  }
                  Navigator.pop(context, (document, selected));
                },
          child: const Text('Enviar ticket'),
        ),
      ],
    );
  }
}
