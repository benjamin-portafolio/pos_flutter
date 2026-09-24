import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../application/config/app_config_controller.dart';
import '../../../core/di/injection.dart';
import '../../../domain/creditos/customer_account.dart';
import '../../../domain/repositories/confirmed_sale_repository.dart';
import '../../../domain/repositories/customer_account_repository.dart';
import '../../../domain/ventas/confirmed_sale.dart';
import 'customer_statement_image_generator.dart';
import 'models/customer_statement_display.dart';

/// Vista previa del comprobante de estado de cuenta. La imagen mostrada y la
/// imagen compartida son exactamente las mismas. Compartir es una acción
/// explícita del usuario.
class CustomerStatementScreen extends StatefulWidget {
  const CustomerStatementScreen({
    required this.clienteId,
    required this.clienteNombre,
    this.operationId,
    this.repository,
    this.salesRepository,
    this.businessName,
    this.shareReceipt,
    super.key,
  });

  final String clienteId;
  final String clienteNombre;

  /// Abono recién registrado: cuando se provee, el comprobante incluye la
  /// sección de recibos liquidados por ese abono.
  final String? operationId;
  final CustomerAccountRepository? repository;
  final ConfirmedSaleRepository? salesRepository;
  final String? businessName;
  final Future<ShareResult> Function(ShareParams)? shareReceipt;

  @override
  State<CustomerStatementScreen> createState() =>
      _CustomerStatementScreenState();
}

class _CustomerStatementScreenState extends State<CustomerStatementScreen> {
  late final Stream<CustomerAccount> _account =
      (widget.repository ?? getIt<CustomerAccountRepository>()).watchAccount(
        widget.clienteId,
      );
  late final Stream<List<ConfirmedSale>> _sales =
      (widget.salesRepository ?? getIt<ConfirmedSaleRepository>()).watchSales();
  late final String _businessName =
      widget.businessName ?? getIt<AppConfigController>().config.businessName;

  Future<Uint8List>? _image;
  String? _imageKey;
  bool _sharing = false;

  String _keyFor(
    CustomerAccount account,
    List<ConfirmedSale> sales,
    String? operationId,
  ) => [
    operationId ?? '',
    for (final e in account.entries)
      '${e.id}:${e.amountMinor}:${e.occurredAtMs}',
    for (final sale in sales) sale.id,
  ].join('|');

  Future<void> _share(Uint8List bytes, BuildContext context) async {
    if (_sharing) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _sharing = true);
    try {
      await (widget.shareReceipt ?? SharePlus.instance.share)(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'image/png')],
          fileNameOverrides: ['estado-cuenta.png'],
          title: 'Cuenta de ${widget.clienteNombre}',
          sharePositionOrigin: origin,
          downloadFallbackEnabled: false,
        ),
      );
      // Abrir o cerrar el selector no confirma la entrega al destinatario.
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo compartir el estado de cuenta.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Widget _content(Widget child, {Uint8List? bytes}) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Builder(
          builder: (context) => FilledButton.tonalIcon(
            onPressed: bytes == null || _sharing
                ? null
                : () => _share(bytes, context),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Compartir'),
          ),
        ),
      ),
      if (bytes != null)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            'Para enviar el comprobante, elige la aplicación en el menú de compartir.',
            textAlign: TextAlign.center,
          ),
        ),
      Expanded(child: child),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Estado de cuenta')),
    backgroundColor: const Color(0xFFF0F0F0),
    body: SafeArea(
      child: StreamBuilder<CustomerAccount>(
        stream: _account,
        builder: (context, accountSnap) {
          if (accountSnap.hasError) {
            return _content(
              const Center(
                child: Text('No se pudo cargar el estado de cuenta.'),
              ),
            );
          }
          if (!accountSnap.hasData) {
            return _content(
              const Center(child: CircularProgressIndicator()),
            );
          }
          return StreamBuilder<List<ConfirmedSale>>(
            stream: _sales,
            builder: (context, salesSnap) {
              if (salesSnap.hasError) {
                return _content(
                  const Center(
                    child: Text('No se pudo cargar el estado de cuenta.'),
                  ),
                );
              }
              if (!salesSnap.hasData) {
                return _content(
                  const Center(child: CircularProgressIndicator()),
                );
              }
              final account = accountSnap.data!;
              final sales = salesSnap.data!;
              final statement = CustomerStatement.build(
                clienteNombre: widget.clienteNombre,
                businessName: _businessName,
                account: account,
                sales: sales,
                operationId: widget.operationId,
              );
              final key = _keyFor(account, sales, widget.operationId);
              if (_image == null || _imageKey != key) {
                _imageKey = key;
                _image = CustomerStatementImageGenerator().generate(statement);
              }
              return FutureBuilder<Uint8List>(
                future: _image!,
                builder: (context, image) {
                  if (image.hasError) {
                    return _content(
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'No se pudo generar la imagen del estado de cuenta.',
                            ),
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
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ),
    ),
  );
}