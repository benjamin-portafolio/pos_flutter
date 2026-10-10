import 'package:flutter/material.dart';

import '../../../application/commands/cotizaciones/cotizacion_command_service.dart';
import '../../../application/commands/cotizaciones/recuperar_cotizacion_command.dart';
import '../../../application/sync/quotation_recovery_line_exception.dart';
import '../../../core/di/injection.dart';
import '../../../domain/cotizaciones/quotation.dart';
import '../../../domain/cotizaciones/quotation_status.dart';
import '../../../domain/repositories/confirmed_sale_repository.dart';
import '../../../domain/repositories/quotation_repository.dart';
import '../caja/sale_receipt_screen.dart';
import 'models/quotation_display.dart';
import 'quotation_estimate_builder.dart';
import 'quotation_ticket_screen.dart';

class QuotationDetailScreen extends StatefulWidget {
  const QuotationDetailScreen({
    required this.quotationId,
    this.repository,
    this.commands,
    this.sales,
    super.key,
  });
  final String quotationId;
  final QuotationRepository? repository;
  final CotizacionCommandService? commands;
  final ConfirmedSaleRepository? sales;

  @override
  State<QuotationDetailScreen> createState() => _QuotationDetailScreenState();
}

class _QuotationDetailScreenState extends State<QuotationDetailScreen> {
  late final _repository = widget.repository ?? getIt<QuotationRepository>();
  late Stream<Quotation?> _document = _repository.watchById(widget.quotationId);
  bool _busy = false;
  int _subscription = 0;
  RecuperarCotizacionCommand? _intent;
  String? _error;

  void _reload() => setState(() {
    _document = _repository.watchById(widget.quotationId);
    _subscription++;
  });

  Future<void> _recover(Quotation quotation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (quotation.lastEventId == null) {
        throw StateError('La cotización no tiene una revisión válida.');
      }
      if (_intent?.expectedQuotationEventId != quotation.lastEventId) {
        _intent = RecuperarCotizacionCommand(
          quotationId: quotation.id,
          expectedQuotationEventId: quotation.lastEventId!,
        );
      }
      final result =
          await (widget.commands ?? getIt<CotizacionCommandService>())
              .recuperar(_intent!);
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (!result.draftAvailable) {
        setState(
          () => _error =
              'Esa captura ya no está disponible. Consulta el estado actual y vuelve a intentar.',
        );
        _intent = null;
        return;
      }
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      final message = switch (error) {
        QuotationRecoveryLineException() =>
          '${quotation.items.where((line) => line.id == error.quotationItemId).firstOrNull?.productName ?? 'Artículo'}: ${error.reason} La cotización se conserva guardada.',
        StateError() => error.message,
        _ =>
          'No se pudo recuperar la cotización. Los datos se conservan; intenta nuevamente.',
      };
      setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDocument(Quotation quotation, {bool sale = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => sale
              ? SaleReceiptScreen(
                  saleId: quotation.currentSaleId!,
                  repository: widget.sales,
                )
              : QuotationTicketScreen(
                  quotationId: quotation.id,
                  repository: _repository,
                ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Detalle de cotización')),
    body: StreamBuilder<Quotation?>(
      key: ValueKey(_subscription),
      stream: _document,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('No se pudo cargar la cotización.'),
                TextButton(onPressed: _reload, child: const Text('Reintentar')),
              ],
            ),
          );
        }
        if (!snapshot.hasData &&
            snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final quotation = snapshot.data;
        if (quotation == null) {
          return const Center(child: Text('No se encontró la cotización.'));
        }
        return QuotationEstimateBuilder(
          quotation: quotation,
          repository: _repository,
          builder: (estimate) {
            final display = QuotationDisplay(quotation, estimate);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Cotización ${quotation.id}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('Fecha de creación: ${display.date}'),
                Text('Cálculo: ${display.calculatedAt}'),
                Text(display.status),
                Text('Total estimado actual: ${display.total}'),
                const Text(QuotationDisplay.recoveryNotice),
                const Divider(),
                for (final row in display.itemRows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row[0]),
                        Text('${row[2]} × ${row[1]}'),
                        Text(row[3]),
                      ],
                    ),
                  ),
                const Divider(),
                Text(QuotationDisplay.legend),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_error!),
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _openDocument(quotation),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Ver ticket'),
                ),
                if (quotation.status == QuotationStatus.vendida)
                  OutlinedButton(
                    onPressed: _busy || quotation.currentSaleId == null
                        ? null
                        : () => _openDocument(quotation, sale: true),
                    child: const Text('Ver venta'),
                  )
                else
                  FilledButton(
                    onPressed: _busy ? null : () => _recover(quotation),
                    child: Text(
                      _busy
                          ? 'Procesando…'
                          : quotation.status == QuotationStatus.enVenta
                          ? 'Continuar venta'
                          : 'Recuperar en Caja',
                    ),
                  ),
              ],
            );
          },
        );
      },
    ),
  );
}
