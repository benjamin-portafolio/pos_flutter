import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/di/injection.dart';
import '../../../domain/repositories/confirmed_sale_repository.dart';
import '../../../domain/ventas/confirmed_sale.dart';
import 'models/sale_receipt_display.dart';
import 'sale_receipt_image_generator.dart';

class SaleReceiptScreen extends StatefulWidget {
  const SaleReceiptScreen({
    required this.saleId,
    this.repository,
    this.shareReceipt,
    super.key,
  });

  final String saleId;
  final ConfirmedSaleRepository? repository;
  final Future<ShareResult> Function(ShareParams)? shareReceipt;

  @override
  State<SaleReceiptScreen> createState() => _SaleReceiptScreenState();
}

class _SaleReceiptScreenState extends State<SaleReceiptScreen> {
  late final _sales = (widget.repository ?? getIt<ConfirmedSaleRepository>())
      .watchSales();
  SaleReceiptDisplay? _receipt;
  Future<Uint8List>? _image;
  bool _sharing = false;

  Future<void> _shareReceipt(Uint8List bytes, BuildContext context) async {
    if (_sharing) return;
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() => _sharing = true);
    try {
      await (widget.shareReceipt ?? SharePlus.instance.share)(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'image/png')],
          fileNameOverrides: [
            'ticket-${widget.saleId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.png',
          ],
          title: 'Selecciona WhatsApp para compartir el ticket',
          sharePositionOrigin: origin,
          downloadFallbackEnabled: false,
        ),
      );
      // Abrir o cerrar el selector no confirma la entrega al destinatario.
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo compartir el ticket. Inténtalo de nuevo.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Widget _content(Widget child, {Uint8List? bytes}) => Column(
    children: [
      _ReceiptOptions(
        onShare: bytes == null || _sharing
            ? null
            : (context) => _shareReceipt(bytes, context),
      ),
      if (bytes != null)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            'Para enviar el ticket, elige WhatsApp en el menú de compartir.',
            textAlign: TextAlign.center,
          ),
        ),
      Expanded(child: child),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Recibo')),
    backgroundColor: const Color(0xFFF0F0F0),
    body: SafeArea(
      child: StreamBuilder<List<ConfirmedSale>>(
        stream: _sales,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _content(
              const Center(
                child: Text('No se pudo cargar el recibo de la venta.'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return _content(const Center(child: CircularProgressIndicator()));
          }
          final sale = snapshot.data!
              .where((sale) => sale.id == widget.saleId)
              .firstOrNull;
          if (sale == null) {
            return _content(
              const Center(child: Text('No se encontró la venta.')),
            );
          }
          // Los datos del cobro son inmutables; cambios en su estado de
          // entrega no necesitan volver a dibujar la imagen.
          final receipt = _receipt ??= SaleReceiptDisplay(sale);
          _image ??= SaleReceiptImageGenerator().generate(receipt);
          return FutureBuilder<Uint8List>(
            future: _image,
            builder: (context, image) {
              if (image.hasError) {
                return _content(
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('No se pudo generar la imagen del recibo.'),
                        TextButton(
                          onPressed: () => setState(() => _image = null),
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
                        semanticLabel: receipt.semanticLabel,
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
      ),
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Nueva venta'),
        ),
      ),
    ),
  );
}

/// Compartir y WhatsApp abren el mismo selector para compartir la imagen.
class _ReceiptOptions extends StatelessWidget {
  const _ReceiptOptions({this.onShare});

  final ValueChanged<BuildContext>? onShare;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            for (final option in const [
              ('Compartir', Icons.share_outlined),
              ('SMS', Icons.sms_outlined),
              ('WhatsApp', Icons.chat_outlined),
              ('Descargar', Icons.file_download_outlined),
              ('Imprimir', Icons.print_outlined),
              ('Más opciones', Icons.more_vert),
            ])
              Builder(
                builder: (context) => IconButton(
                  onPressed:
                      (option.$1 == 'Compartir' || option.$1 == 'WhatsApp') &&
                          onShare != null
                      ? () => onShare!(context)
                      : null,
                  tooltip: option.$1,
                  icon: Icon(option.$2),
                ),
              ),
          ],
        ),
        const Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            OutlinedButton(onPressed: null, child: Text('Regresar')),
            OutlinedButton(onPressed: null, child: Text('Borrar')),
            OutlinedButton(onPressed: null, child: Text('Editar')),
          ],
        ),
      ],
    ),
  );
}
