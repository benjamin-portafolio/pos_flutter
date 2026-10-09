import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../application/commands/ventas/limpiar_venta_borrador_command.dart';
import '../../../application/commands/ventas/venta_borrador_command_service.dart';
import '../../../core/di/injection.dart';
import '../../../domain/cotizaciones/quotation.dart';
import '../../../domain/repositories/quotation_repository.dart';
import '../../tickets/ticket_document.dart';
import '../../tickets/ticket_image_generator.dart';
import 'models/quotation_display.dart';
import 'quotation_estimate_builder.dart';

class QuotationTicketScreen extends StatefulWidget {
  const QuotationTicketScreen({
    required this.quotationId,
    this.repository,
    this.emissionDraft,
    this.draftCommands,
    this.shareTicket,
    this.generateImage,
    super.key,
  });

  final String quotationId;
  final QuotationRepository? repository;

  /// Sólo la emisión desde Caja puede limpiar la revisión que acaba de guardar.
  /// Consultar el historial (incluida una captura ya vinculada) no lo proporciona.
  final LimpiarVentaBorradorCommand? emissionDraft;
  final VentaBorradorCommandService? draftCommands;
  final Future<ShareResult> Function(ShareParams)? shareTicket;
  final Future<Uint8List> Function(TicketDocument)? generateImage;

  @override
  State<QuotationTicketScreen> createState() => _QuotationTicketScreenState();
}

class _QuotationTicketScreenState extends State<QuotationTicketScreen> {
  late final _repository = widget.repository ?? getIt<QuotationRepository>();
  late Stream<Quotation?> _document = _repository.watchById(widget.quotationId);
  QuotationDisplay? _display;
  Future<Uint8List>? _image;
  bool _busy = false;
  int _subscription = 0;

  void _reload() => setState(() {
    _display = null;
    _image = null;
    _document = _repository.watchById(widget.quotationId);
    _subscription++;
  });

  Future<void> _share(Uint8List bytes, BuildContext buttonContext) async {
    if (_busy) return;
    // La siguiente lectura puede regenerar el preview mientras el selector
    // está abierto. Esta operación conserva su propia imagen completa.
    final sharedBytes = Uint8List.fromList(bytes);
    final box = buttonContext.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() => _busy = true);
    try {
      await (widget.shareTicket ?? SharePlus.instance.share)(
        ShareParams(
          files: [XFile.fromData(sharedBytes, mimeType: 'image/png')],
          fileNameOverrides: [
            'cotizacion-${widget.quotationId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.png',
          ],
          title: 'Selecciona WhatsApp para compartir la cotización',
          sharePositionOrigin: origin,
          downloadFallbackEnabled: false,
        ),
      );
      // El resultado del selector no acredita entrega ni limpia la captura.
    } catch (_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo compartir la cotización. Inténtalo de nuevo.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newDraft() async {
    if (_busy) return;
    final command = widget.emissionDraft;
    if (command == null || command.expectedDraftEventId == null) return;
    setState(() => _busy = true);
    try {
      await (widget.draftCommands ?? getIt<VentaBorradorCommandService>())
          .limpiar(command);
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError
                  ? '${error.message} La cotización sigue guardada; vuelve a Caja para revisar la captura.'
                  : 'No se pudo iniciar una nueva captura. La cotización y la captura se conservan.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _content(Widget child, {Uint8List? bytes}) => Column(
    children: [
      Wrap(
        alignment: WrapAlignment.center,
        children: [
          for (final option in const [
            ('Compartir', Icons.share_outlined),
            ('WhatsApp', Icons.chat_outlined),
          ])
            Builder(
              builder: (context) => IconButton(
                tooltip: option.$1,
                icon: Icon(option.$2),
                onPressed: bytes == null || _busy
                    ? null
                    : () => _share(bytes, context),
              ),
            ),
          const IconButton(
            onPressed: null,
            tooltip: 'Imprimir',
            icon: Icon(Icons.print_outlined),
          ),
        ],
      ),
      if (bytes != null)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            'Para enviar la cotización, elige WhatsApp en el menú de compartir.',
            textAlign: TextAlign.center,
          ),
        ),
      Expanded(child: child),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _busy
                ? null
                : widget.emissionDraft == null
                ? () => Navigator.of(context).pop()
                : _display == null
                ? null
                : _newDraft,
            child: Text(
              widget.emissionDraft == null ? 'Cerrar' : 'Nueva captura',
            ),
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ticket de cotización')),
    backgroundColor: const Color(0xFFF0F0F0),
    body: SafeArea(
      child: StreamBuilder<Quotation?>(
        key: ValueKey(_subscription),
        stream: _document,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            _display = null;
            _image = null;
            return _content(
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No se pudo cargar la cotización.'),
                    TextButton(
                      onPressed: _busy ? null : _reload,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData &&
              snapshot.connectionState == ConnectionState.waiting) {
            return _content(const Center(child: CircularProgressIndicator()));
          }
          final quotation = snapshot.data;
          if (quotation == null) {
            _display = null;
            _image = null;
            return _content(
              const Center(child: Text('No se encontró la cotización.')),
            );
          }
          return QuotationEstimateBuilder(
            quotation: quotation,
            repository: _repository,
            builder: (estimate) {
              if (_display?.quotation != quotation ||
                  _display?.estimate != estimate) {
                _display = QuotationDisplay(quotation, estimate);
                _image = null;
              }
              final display = _display!;
              _image ??= Future.sync(
                () => (widget.generateImage ?? TicketImageGenerator().generate)(
                  display.ticket,
                ),
              );
              return FutureBuilder<Uint8List>(
                future: _image,
                builder: (context, image) {
                  if (image.connectionState != ConnectionState.done) {
                    return _content(
                      const Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (image.hasError) {
                    return _content(
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'La cotización está guardada. No se pudo generar la imagen.',
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() => _image = null),
                              child: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  if (!image.hasData) {
                    return _content(
                      const Center(child: CircularProgressIndicator()),
                    );
                  }
                  return _content(
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 600),
                          child: Image.memory(
                            image.data!,
                            width: double.infinity,
                            fit: BoxFit.fitWidth,
                            semanticLabel: display.semanticLabel,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ),
                    ),
                    bytes: image.data!,
                  );
                },
              );
            },
          );
        },
      ),
    ),
  );
}
