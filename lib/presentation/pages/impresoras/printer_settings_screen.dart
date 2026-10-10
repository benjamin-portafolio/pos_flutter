import 'dart:async';

import 'package:flutter/material.dart';

import '../../../application/printing/printer_device.dart';
import '../../../application/printing/printer_exception.dart';
import '../../../application/printing/printer_gateway.dart';
import '../../../application/printing/printer_profile.dart';
import '../../../application/printing/printer_settings.dart';
import '../../../application/printing/printer_settings_controller.dart';
import '../../../application/printing/printer_settings_exception.dart';
import '../../../application/printing/ticket_print_service.dart';
import 'bonded_printers_screen.dart';
import 'printer_access.dart';
import 'printer_failure_message.dart';
import 'printer_profile_dialog.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({
    super.key,
    required this.controller,
    required this.gateway,
    required this.printService,
  });

  final PrinterSettingsController controller;
  final PrinterGateway gateway;
  final TicketPrintService printService;

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  late final StreamSubscription<PrinterSettings> _subscription;
  late final StreamSubscription<bool> _printSubscription;
  bool _loading = false;
  bool _saving = false;
  bool _sending = false;
  String? _printMessage;
  String? _printDestination;

  @override
  void initState() {
    super.initState();
    _subscription = widget.controller.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _printSubscription = widget.printService.busyChanges.listen((_) {
      if (mounted) setState(() {});
    });
    if (!widget.controller.loaded) _load();
  }

  @override
  void dispose() {
    _subscription.cancel();
    _printSubscription.cancel();
    // The global service retains ownership of any print already handed to it.
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await widget.controller.load();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        _notice(
          'No se pudieron guardar los ajustes. Se conserva el último estado confirmado.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _notice(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _add() async {
    final device = await Navigator.of(context).push<PrinterDevice>(
      MaterialPageRoute(
        builder: (_) => BondedPrintersScreen(gateway: widget.gateway),
      ),
    );
    if (!mounted || device == null) return;
    PrinterProfile? existing;
    for (final profile in widget.controller.settings.printers) {
      if (profile.address == device.address.trim().toUpperCase()) {
        existing = profile;
      }
    }
    await _edit(device, existing);
  }

  Future<void> _edit(PrinterDevice device, PrinterProfile? existing) async {
    final profile = await showDialog<PrinterProfile>(
      context: context,
      builder: (_) => PrinterProfileDialog(device: device, profile: existing),
    );
    if (!mounted || profile == null) return;
    await _save(() => widget.controller.upsert(profile));
  }

  Future<void> _remove(PrinterProfile profile) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quitar impresora'),
        content: Text(
          'Quitar ${profile.alias} (${profile.address}) de esta app. '
          'El dispositivo seguirá vinculado en Android. '
          'Si es la predeterminada, la selección quedará vacía.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true) return;
    await _save(() => widget.controller.remove(profile.address));
  }

  Future<void> _recover() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recuperar configuración'),
        content: const Text(
          'Se conservará una copia del archivo original y se '
          'creará una configuración vacía. Deberás agregar tus impresoras de nuevo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Conservar y reiniciar'),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true) return;
    await _save(() async {
      final archive = await widget.controller.recover();
      if (mounted) {
        _notice('Configuración recuperada. Original conservado en: $archive');
      }
    });
  }

  Future<void> _print(PrinterProfile profile) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _printDestination =
          '${profile.alias} · ${profile.address} · ${profile.paper == PrinterPaper.mm58 ? 58 : 80} mm';
      _printMessage = 'Preparando prueba para $_printDestination';
    });
    try {
      final result = await widget.printService.printTest(
        profile,
        beforeSend: () async {
          final allowed = await requestPrinterAccess(
            widget.gateway,
            timeout: null,
            isActive: () =>
                mounted && (ModalRoute.of(context)?.isCurrent ?? true),
          );
          if (allowed &&
              _sending &&
              mounted &&
              (ModalRoute.of(context)?.isCurrent ?? true)) {
            setState(
              () => _printMessage = 'Enviando prueba a $_printDestination',
            );
          }
          return allowed;
        },
        isActive: () => mounted && (ModalRoute.of(context)?.isCurrent ?? true),
      );
      if (!mounted) return;
      setState(() {
        _printMessage = result.sent
            ? 'Prueba enviada a $_printDestination. El envío de bytes no confirma la impresión física; revisa el papel.'
            : '${printerFailureMessage(result.failure!)}${result.mayHavePrinted ? ' Puede haberse impreso una parte; revisa el ticket antes de reimprimir.' : ''}';
      });
    } on PrinterException catch (error) {
      if (mounted) {
        setState(() => _printMessage = printerFailureMessage(error.failure));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _printMessage = printerFailureMessage(
            PrinterFailure.transportError,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final settings = controller.settings;
    final canEdit = controller.canEdit && !_saving && !_loading;
    return Scaffold(
      appBar: AppBar(title: const Text('Impresoras')),
      bottomNavigationBar: _printDestination == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_sending) const LinearProgressIndicator(),
                    Text('Destino de prueba: $_printDestination'),
                    if (_printMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(_printMessage!),
                    ],
                  ],
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Impresoras de esta instalación. Configuración local disponible en ambos modos.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: canEdit ? _add : null,
            icon: const Icon(Icons.add),
            label: const Text('Agregar impresora'),
          ),
          if (_loading || _saving) const LinearProgressIndicator(),
          if (controller.loadError case final error?) ...[
            const SizedBox(height: 16),
            Text(switch (error.failure) {
              PrinterSettingsFailure.corrupt =>
                'El archivo de impresoras está dañado. El original se conserva hasta que decidas recuperarlo.',
              PrinterSettingsFailure.unsupportedVersion =>
                'La versión del archivo de impresoras no es compatible. El original se conserva hasta que decidas recuperarlo.',
              _ =>
                'No se pudo leer la configuración de impresoras. Intenta recargar.',
            }),
            OutlinedButton(
              onPressed: _loading || _saving ? null : _load,
              child: const Text('Recargar configuración'),
            ),
            if (error.canRecover)
              OutlinedButton(
                onPressed: _saving || _loading ? null : _recover,
                child: const Text('Recuperar configuración'),
              ),
          ],
          const SizedBox(height: 16),
          Text(
            settings.defaultAddress == null
                ? 'Sin impresora predeterminada.'
                : 'Predeterminada: ${settings.defaultAddress}',
          ),
          if (settings.defaultAddress != null)
            TextButton(
              onPressed: canEdit
                  ? () => _save(() => controller.setDefault(null))
                  : null,
              child: const Text('Dejar sin predeterminada'),
            ),
          if (settings.printers.isEmpty &&
              controller.loadError == null &&
              !_loading)
            const Text('No hay impresoras guardadas.'),
          for (final profile in settings.printers)
            Card(
              key: ValueKey(profile.address),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.alias,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${profile.address} · ${profile.paper == PrinterPaper.mm58 ? 58 : 80} mm',
                    ),
                    if (settings.defaultAddress == profile.address)
                      const Text('Predeterminada'),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: canEdit
                              ? () => _edit(
                                  PrinterDevice(
                                    address: profile.address,
                                    name: profile.alias,
                                  ),
                                  profile,
                                )
                              : null,
                          child: const Text('Editar'),
                        ),
                        TextButton(
                          onPressed:
                              canEdit &&
                                  settings.defaultAddress != profile.address
                              ? () => _save(
                                  () => controller.setDefault(profile.address),
                                )
                              : null,
                          child: const Text('Elegir predeterminada'),
                        ),
                        TextButton(
                          onPressed: canEdit ? () => _remove(profile) : null,
                          child: const Text('Quitar'),
                        ),
                        OutlinedButton(
                          onPressed: canEdit && !_sending
                              ? () => _print(profile)
                              : null,
                          child: const Text('Imprimir prueba'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
