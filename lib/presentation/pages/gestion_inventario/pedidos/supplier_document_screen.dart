import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../application/tickets/ticket_document.dart';
import '../../../tickets/ticket_image_generator.dart';
import '../../../tickets/ticket_print_action.dart';

/// The selected immutable document stays fixed throughout preview/share/print.
class SupplierDocumentScreen extends StatefulWidget {
  const SupplierDocumentScreen({
    required this.document,
    this.generateImage,
    this.shareTicket,
    this.statusUpdates,
    this.initialStatus,
    super.key,
  });
  final TicketDocument document;
  final Stream<String>? statusUpdates;
  final String? initialStatus;
  final Future<Uint8List> Function(TicketDocument)? generateImage;
  final Future<ShareResult> Function(ShareParams)? shareTicket;
  @override
  State<SupplierDocumentScreen> createState() => _SupplierDocumentScreenState();
}

class _SupplierDocumentScreenState extends State<SupplierDocumentScreen> {
  late final document = widget.document;
  late Future<Uint8List> image = _generate();
  bool busy = false;
  StreamSubscription<String>? subscription;
  late String? status = widget.initialStatus;
  bool get invalid =>
      status == 'conflict' || status == 'rejected' || status == 'unavailable';
  @override
  void initState() {
    super.initState();
    subscription = widget.statusUpdates?.listen(
      (value) {
        if (mounted) setState(() => status = value);
      },
      onError: (Object e) {
        if (mounted) setState(() => status = 'unavailable');
      },
    );
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  Future<Uint8List> _generate() => Future.sync(
    () => (widget.generateImage ?? TicketImageGenerator().generate)(document),
  );
  Future<void> _share(Uint8List bytes, BuildContext button) async {
    if (busy || invalid) return;
    final selected = Uint8List.fromList(bytes);
    final box = button.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() => busy = true);
    try {
      await (widget.shareTicket ?? SharePlus.instance.share)(
        ShareParams(
          files: [XFile.fromData(selected, mimeType: 'image/png')],
          fileNameOverrides: [
            'documento-${document.identifier.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.png',
          ],
          title: document.title,
          sharePositionOrigin: origin,
          downloadFallbackEnabled: false,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo compartir. Puedes reintentar con el mismo documento.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ticket del documento')),
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Compartir, cancelar el selector o reimprimir no modifica el pedido ni inventario y no acredita entrega.',
            ),
          ),
          if (invalid)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'La recepción seleccionada fue rechazada o no se puede acreditar su estado. Consulta el detalle vigente. Esta imagen conserva la revisión seleccionada.',
              ),
            ),
          TicketPrintAction(document: invalid ? null : document),
          Expanded(
            child: FutureBuilder<Uint8List>(
              future: image,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton(
                      onPressed: () => setState(() {
                        image = _generate();
                      }),
                      child: const Text(
                        'No se pudo generar la imagen. Reintentar',
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Column(
                  children: [
                    Builder(
                      builder: (button) => TextButton.icon(
                        onPressed: busy || invalid
                            ? null
                            : () => _share(snapshot.data!, button),
                        icon: const Icon(Icons.share),
                        label: const Text('Compartir'),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 600),
                            child: Image.memory(
                              snapshot.data!,
                              semanticLabel: document.title,
                              fit: BoxFit.fitWidth,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
