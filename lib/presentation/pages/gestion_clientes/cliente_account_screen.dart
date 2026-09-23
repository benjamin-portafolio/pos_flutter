import 'customer_account_receipt_image_generator.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/di/injection.dart';
import '../../../domain/clientes/cliente.dart';
import '../../../domain/creditos/customer_account.dart';
import '../../../domain/creditos/account_entry.dart';
import '../../../domain/repositories/customer_account_repository.dart';
import '../caja/sale_receipt_screen.dart';
import 'registrar_abono_screen.dart';
import 'customer_account_display.dart';
import 'cliente_form_screen.dart';
import '../../../domain/repositories/cliente_repository.dart';
import '../../../application/commands/clientes/cliente_command_service.dart';
import '../../../application/commands/clientes/editar_cliente_command.dart';

class ClienteAccountScreen extends StatefulWidget {
  const ClienteAccountScreen({
    required this.cliente,
    this.repository,
    this.clienteRepository,
    this.commandService,
    super.key,
  });
  final Cliente cliente;
  final ClienteRepository? clienteRepository;
  final ClienteCommandService? commandService;
  final CustomerAccountRepository? repository;
  @override
  State<ClienteAccountScreen> createState() => _ClienteAccountScreenState();
}

class _ClienteAccountScreenState extends State<ClienteAccountScreen> {
  late final _account =
      (widget.repository ?? getIt<CustomerAccountRepository>()).watchAccount(
        widget.cliente.id,
      );
  late final Stream<List<Cliente>> _clientes =
      (widget.clienteRepository ?? getIt<ClienteRepository>()).watchClientes();
  String? _lastOperation;
  Future<void> _edit(Cliente cliente) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ClienteFormScreen(
          cliente: cliente,
          onSave: (result) async {
            final base = cliente.lastEventId;
            if (base == null) {
              throw StateError('El cliente no tiene evento base.');
            }
            await (widget.commandService ?? getIt<ClienteCommandService>())
                .editarCliente(
                  EditarClienteCommand(
                    clienteId: cliente.id,
                    baseEventId: base,
                    nombre: result.nombre,
                    telefono: result.telefono,
                  ),
                );
          },
        ),
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cliente actualizado.')));
    }
  }

  Future<void> _add(Cliente cliente) async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => RegistrarAbonoScreen(cliente: cliente)),
    );
    if (mounted && id != null) setState(() => _lastOperation = id);
  }

  Future<void> _ticket(Cliente cliente, CustomerAccount account) async {
    final text = CustomerAccountDisplay.statement(
      cliente.nombre,
      account,
      operationId: _lastOperation,
    );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Estado de cuenta'),
        content: SingleChildScrollView(child: SelectableText(text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                final box = dialogContext.findRenderObject() as RenderBox?;
                final image = await CustomerAccountReceiptImageGenerator()
                    .generate(text);
                await SharePlus.instance.share(
                  ShareParams(
                    files: [XFile.fromData(image, mimeType: 'image/png')],
                    fileNameOverrides: ['estado-cuenta.png'],
                    title: 'Cuenta de ${cliente.nombre}',
                    sharePositionOrigin: box == null
                        ? null
                        : box.localToGlobal(Offset.zero) & box.size,
                  ),
                );
              } catch (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('No se pudo compartir: $error')),
                  );
                }
              }
            },
            child: const Text('Compartir'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Cliente>>(
    stream: _clientes,
    builder: (context, snapshot) {
      final cliente =
          snapshot.data?.where((c) => c.id == widget.cliente.id).firstOrNull ??
          widget.cliente;
      return _detail(cliente);
    },
  );

  Widget _detail(Cliente cliente) => Scaffold(
    appBar: AppBar(
      title: Text(cliente.nombre),
      actions: [
        TextButton.icon(
          onPressed: cliente.active ? () => _edit(cliente) : null,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Editar'),
        ),
      ],
    ),
    body: StreamBuilder<CustomerAccount>(
      stream: _account,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('No se pudo cargar la cuenta.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final account = snapshot.data!;
        final balance = account.balanceMinor;
        final pending = account.entries
            .where((e) => !e.isPayment && account.pendingMinor(e) > 0)
            .length;
        var running = BigInt.zero;
        final balances = <String, BigInt>{};
        for (final e in account.entries) {
          running += BigInt.from(e.isPayment ? e.amountMinor : -e.amountMinor);
          balances[e.id] = running;
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            Text(cliente.telefono ?? 'Sin teléfono registrado'),
            SelectableText(
              'Cliente: ${widget.cliente.id}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      balance.isNegative
                          ? 'Debe'
                          : balance == BigInt.zero
                          ? 'Cuenta saldada'
                          : 'Saldo a favor',
                    ),
                    Text(
                      CustomerAccountDisplay.money(balance),
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            color: balance.isNegative
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.primary,
                          ),
                    ),
                    Text('$pending ventas pendientes'),
                  ],
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _ticket(cliente, account),
              icon: const Icon(Icons.receipt_long),
              label: const Text('Ver / compartir estado de cuenta'),
            ),
            const SizedBox(height: 20),
            Text(
              'Historial de movimientos',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (account.entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Todavía no hay créditos ni abonos.'),
              ),
            for (final e in account.entries.reversed)
              _movement(e, account, balances[e.id]!),
          ],
        );
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _add(cliente),
      icon: const Icon(Icons.add),
      label: const Text('Registrar abono'),
    ),
  );
  Widget _movement(AccountEntry e, CustomerAccount account, BigInt balance) {
    final applications = account.allocations.where(
      (a) => e.isPayment ? a.paymentId == e.id : a.creditId == e.id,
    );
    return Card(
      child: ExpansionTile(
        leading: Icon(e.isPayment ? Icons.south_west : Icons.north_east),
        title: Text(
          '${e.isPayment ? 'Abono' : 'Compra a crédito'} · ${CustomerAccountDisplay.money(BigInt.from(e.amountMinor))}',
        ),
        subtitle: Text(
          '${e.date}\nSaldo: ${CustomerAccountDisplay.money(balance)} · ${CustomerAccountDisplay.status(e)}',
        ),
        childrenPadding: const EdgeInsets.all(16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText('Folio: ${e.id}'),
          if (!e.isPayment)
            Text(
              'Pendiente: ${CustomerAccountDisplay.money(BigInt.from(account.pendingMinor(e)))}${account.pendingMinor(e) == 0 ? ' · Liquidada' : ''}',
            ),
          if (e.isPayment) ...[
            Text(
              'Método: ${e.method == 'cash' ? 'Efectivo' : 'Transferencia'}',
            ),
            Text(
              'Disponible a favor: ${CustomerAccountDisplay.money(BigInt.from(account.availableMinor(e)))}',
            ),
          ],
          if (e.reference != null) Text(e.reference!),
          for (final a in applications)
            Text(
              '${e.isPayment ? 'A venta ${a.creditId}' : 'Abono ${a.paymentId}'}: ${CustomerAccountDisplay.money(BigInt.from(a.amountMinor))}',
            ),
          Text('Registró: ${e.userId} · Dispositivo: ${e.deviceId}'),
          if (e.reason != null)
            Text(
              e.reason!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (e.saleId != null)
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => SaleReceiptScreen(saleId: e.saleId!),
                ),
              ),
              child: const Text('Ver venta y productos'),
            ),
        ],
      ),
    );
  }
}
