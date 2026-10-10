import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../application/printing/printer_exception.dart';
import '../../application/printing/printer_gateway.dart';
import '../../application/printing/printer_profile.dart';
import '../../application/printing/printer_settings_controller.dart';
import '../../application/printing/ticket_print_service.dart';
import '../../application/tickets/ticket_document.dart';
import '../../core/di/injection.dart';
import '../pages/impresoras/printer_access.dart';
import '../pages/impresoras/printer_failure_message.dart';
import '../pages/impresoras/printer_settings_screen.dart';
import 'ticket_printer_dialog.dart';

/// Shared manual action. Opening, resuming and rebuilding never start a send.
class TicketPrintAction extends StatefulWidget {
  const TicketPrintAction({
    required this.document,
    this.controller,
    this.gateway,
    this.service,
    super.key,
  });
  final TicketDocument? document;
  final PrinterSettingsController? controller;
  final PrinterGateway? gateway;
  final TicketPrintService? service;

  @override
  State<TicketPrintAction> createState() => _TicketPrintActionState();
}

class _TicketPrintActionState extends State<TicketPrintAction>
    with WidgetsBindingObserver {
  late final _controller =
      widget.controller ?? _registered<PrinterSettingsController>();
  late final _gateway = widget.gateway ?? _registered<PrinterGateway>();
  late final _service = widget.service ?? _registered<TicketPrintService>();
  StreamSubscription<bool>? _busyChanges;
  var _intent = 0;
  bool _pending = false;
  String? _message;

  T? _registered<T extends Object>() =>
      getIt.isRegistered<T>() ? getIt<T>() : null;
  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows);
  bool _active(int intent) =>
      mounted &&
      intent == _intent &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _busyChanges = _service?.busyChanges.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _intent++; // invalidates pending permission/selector and old UI callbacks
    }
  }

  @override
  void dispose() {
    _intent++;
    WidgetsBinding.instance.removeObserver(this);
    _busyChanges?.cancel();
    super.dispose();
  }

  Future<void> _configure() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => PrinterSettingsScreen(
        controller: _controller!,
        gateway: _gateway!,
        printService: _service!,
      ),
    ),
  );

  Future<void> _print() async {
    if (_pending || widget.document == null || !_supported) return;
    final intent = ++_intent;
    setState(() {
      _pending = true;
      _message = null;
    });
    try {
      final controller = _controller;
      final service = _service;
      final gateway = _gateway;
      if (controller == null || service == null || gateway == null) {
        setState(
          () => _message = 'La configuración de impresoras no está disponible.',
        );
        return;
      }
      if (service.isBusy) {
        setState(() => _message = printerFailureMessage(PrinterFailure.busy));
        return;
      }
      if (!controller.loaded) await controller.load();
      if (!mounted || !_active(intent)) return;
      if (controller.loadError != null ||
          controller.settings.printers.isEmpty) {
        final open = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Configurar impresoras'),
            content: Text(
              controller.loadError == null
                  ? 'No hay impresoras guardadas. Agrega una en Configuración → Impresoras.'
                  : 'Revisa la configuración de impresoras antes de enviar.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Abrir configuración'),
              ),
            ],
          ),
        );
        if (!mounted || !_active(intent) || open != true) return;
        await _configure();
        return;
      }
      final snapshot = await showDialog<(TicketDocument, PrinterProfile)>(
        context: context,
        builder: (_) => TicketPrinterDialog(
          controller: controller,
          currentDocument: () =>
              mounted && intent == _intent ? widget.document : null,
        ),
      );
      if (!mounted || !_active(intent) || snapshot == null) return;
      final (document, profile) = snapshot;
      final destination =
          '${profile.alias} · ${profile.paper == PrinterPaper.mm58 ? 58 : 80} mm';
      setState(() => _message = 'Preparando y enviando a $destination');
      final result = await service.printTicket(
        document: document,
        profile: profile,
        beforeSend: () => requestPrinterAccess(
          gateway,
          timeout: null,
          isActive: () => _active(intent),
        ),
        isActive: () => _active(intent),
      );
      if (!mounted || !_active(intent)) return;
      setState(
        () => _message = result.sent
            ? (profile.transport == PrinterTransport.windowsSpooler
                  ? 'Windows aceptó el trabajo para $destination. La aceptación no confirma la impresión física; revisa el papel.'
                  : 'Ticket enviado a la impresora: $destination. El envío no confirma la impresión física; revisa el papel.')
            : '${printerFailureMessage(result.failure!)}${result.mayHavePrinted ? ' El envío se interrumpió. Puede haberse impreso una parte; revisa el ticket antes de reimprimir.' : ''}',
      );
    } catch (_) {
      if (_active(intent)) {
        setState(
          () => _message =
              'No se pudo preparar el envío. Puedes intentarlo manualmente.',
        );
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: 'Imprimir',
        icon: const Icon(Icons.print_outlined),
        onPressed:
            widget.document == null ||
                !_supported ||
                _pending ||
                (_service?.isBusy ?? false)
            ? null
            : _print,
      ),
      if (!_supported)
        const Text(
          'Impresión disponible en Android y Windows.',
          textAlign: TextAlign.center,
        ),
      if (_pending && _message != null)
        const SizedBox(width: 160, child: LinearProgressIndicator()),
      if (_message != null)
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Text(_message!, textAlign: TextAlign.center),
        ),
      if (!_pending && (_service?.isBusy ?? false))
        const Text(
          'Servicio de impresión ocupado.',
          textAlign: TextAlign.center,
        ),
    ],
  );
}
