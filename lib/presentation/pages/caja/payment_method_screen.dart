import 'package:flutter/material.dart';
import '../../../application/commands/ventas/confirmar_venta_command.dart';
import '../../../application/commands/ventas/venta_command_service.dart';
import '../../../core/di/injection.dart';
import '../../../domain/clientes/cliente.dart';
import '../../../domain/repositories/cliente_repository.dart';
import '../gestion_clientes/cliente_picker_screen.dart';
import 'cash_payment_screen.dart';
import 'sale_receipt_screen.dart';
import 'models/sale_draft_display.dart';

class PaymentMethodScreen extends StatefulWidget {
  const PaymentMethodScreen({
    required this.totalMinor,
    this.saleId,
    this.expectedDraftEventId,
    this.commandService,
    this.clienteRepository,
    super.key,
  });
  final int totalMinor;
  final String? saleId, expectedDraftEventId;
  final VentaCommandService? commandService;
  final ClienteRepository? clienteRepository;
  @override
  State<PaymentMethodScreen> createState() => _PaymentMethodScreenState();
}

class _PaymentMethodScreenState extends State<PaymentMethodScreen> {
  Cliente? _cliente;
  bool _processing = false;
  Future<void> _selectCliente() async {
    final selected = await Navigator.push<Cliente>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ClientePickerScreen(repository: widget.clienteRepository),
      ),
    );
    if (mounted && selected != null) setState(() => _cliente = selected);
  }

  Future<void> _credit() async {
    if (_processing) return;
    if (_cliente == null) {
      await _selectCliente();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar venta a crédito'),
        content: Text(
          'Se cargarán ${SaleDraftDisplay.money(widget.totalMinor)} a la cuenta de ${_cliente!.nombre}. No se recibe efectivo en esta operación.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar crédito'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _processing) return;
    setState(() => _processing = true);
    try {
      await (widget.commandService ?? getIt<VentaCommandService>()).confirmar(
        ConfirmarVentaCommand(
          saleId: widget.saleId!,
          expectedDraftEventId: widget.expectedDraftEventId!,
          expectedTotalMinor: widget.totalMinor,
          clienteId: _cliente!.id,
          paymentMethod: 'credit',
        ),
      );
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => SaleReceiptScreen(saleId: widget.saleId!),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _cash() async {
    final confirmed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CashPaymentScreen(
          totalMinor: widget.totalMinor,
          saleId: widget.saleId,
          expectedDraftEventId: widget.expectedDraftEventId,
          clienteId: _cliente?.id,
          commandService: widget.commandService,
        ),
      ),
    );
    if (confirmed == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_processing,
    child: Scaffold(
      appBar: AppBar(title: const Text('Cobrar')),
      backgroundColor: const Color(0xFFF0F0F0),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'CLIENTE · OBLIGATORIO PARA CRÉDITO',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Número de teléfono móvil',
                            ),
                            child: Text(_cliente?.telefono ?? '—'),
                          ),
                        ),
                        IconButton(
                          onPressed: _processing ? null : _selectCliente,
                          tooltip: 'Buscar cliente',
                          icon: const Icon(Icons.search),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_cliente?.nombre ?? 'Seleccionar cliente'),
                      subtitle: const Text('Opcional para efectivo'),
                      onTap: _processing ? null : _selectCliente,
                      trailing: _cliente == null
                          ? const Icon(Icons.arrow_drop_down)
                          : IconButton(
                              tooltip: 'Quitar cliente',
                              onPressed: _processing
                                  ? null
                                  : () => setState(() => _cliente = null),
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Seleccione el método de pago',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: LayoutBuilder(
                  builder: (context, constraints) => Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final method in <(String, IconData, VoidCallback?)>[
                        (
                          'Efectivo',
                          Icons.payments_outlined,
                          _processing ? null : _cash,
                        ),
                        (
                          _processing ? 'Registrando…' : 'Crédito del cliente',
                          Icons.account_balance_wallet_outlined,
                          _processing ||
                                  widget.saleId == null ||
                                  widget.totalMinor <= 0
                              ? null
                              : _credit,
                        ),
                        ('Tarjeta de débito', Icons.credit_card, null),
                        (
                          'Tarjeta de crédito',
                          Icons.credit_card_outlined,
                          null,
                        ),
                        (
                          'Transferencia bancaria',
                          Icons.account_balance_outlined,
                          null,
                        ),
                      ])
                        SizedBox(
                          width: (constraints.maxWidth - 12) / 2,
                          child: OutlinedButton(
                            onPressed: method.$3,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 20,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(method.$2, size: 40),
                                const SizedBox(height: 12),
                                Text(method.$1, textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Los abonos se registran desde Gestión de clientes.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
