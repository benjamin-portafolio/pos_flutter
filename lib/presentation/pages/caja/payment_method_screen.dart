import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../application/commands/ventas/confirmar_venta_command.dart';
import '../../../application/commands/ventas/venta_command_service.dart';
import '../../../core/di/injection.dart';
import '../../../domain/clientes/cliente.dart';
import '../../../domain/repositories/cliente_repository.dart';
import '../gestion_clientes/cliente_picker_screen.dart';
import 'card_payment_content.dart';
import 'cash_payment_content.dart';
import 'credit_payment_content.dart';
import 'models/sale_draft_display.dart';
import 'sale_receipt_screen.dart';
import 'transfer_payment_content.dart';

/// Cobro unificado: método de pago como pestañas y confirmación compartida.
class PaymentMethodScreen extends StatefulWidget {
  const PaymentMethodScreen({
    required this.totalMinor,
    this.saleId,
    this.expectedDraftEventId,
    this.commandService,
    this.clienteRepository,
    this.consumeOpeningEnter = false,
    super.key,
  });

  final int totalMinor;
  final String? saleId, expectedDraftEventId;
  final VentaCommandService? commandService;
  final ClienteRepository? clienteRepository;

  /// El cobro se abrió con Enter; la misma pulsación y sus repeticiones no
  /// deben confirmar la venta.
  final bool consumeOpeningEnter;

  @override
  State<PaymentMethodScreen> createState() => _PaymentMethodScreenState();
}

enum _PaymentTab {
  cash('Efectivo'),
  transfer('Transferencia'),
  credit('Crédito'),
  card('Tarjeta');

  const _PaymentTab(this.label);

  final String label;
}

class _PaymentMethodScreenState extends State<PaymentMethodScreen> {
  final _cashKey = GlobalKey<CashPaymentContentState>();
  Cliente? _cliente;
  bool _processing = false;
  var _tab = _PaymentTab.cash;
  late bool _enterArmed;

  bool get _canConfirmSale =>
      widget.saleId != null && widget.expectedDraftEventId != null;

  bool get _canConfirmCredit =>
      _canConfirmSale && widget.totalMinor > 0 && _cliente != null;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _enterArmed =
        !widget.consumeOpeningEnter ||
        !HardwareKeyboard.instance.logicalKeysPressed.any(_isEnterKey);
    _focusCash();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyUpEvent && _isEnterKey(event.logicalKey) && !_enterArmed) {
      setState(() => _enterArmed = true);
    }
    return false;
  }

  void _focusCash() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _tab == _PaymentTab.cash) {
        _cashKey.currentState?.focusReceived();
      }
    });
  }

  void _selectTab(_PaymentTab tab) {
    if (_processing || tab == _tab) return;
    FocusScope.of(context).unfocus();
    setState(() => _tab = tab);
    if (tab == _PaymentTab.cash) _focusCash();
  }

  Future<void> _selectCliente() async {
    if (_processing) return;
    final selected = await Navigator.push<Cliente>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ClientePickerScreen(repository: widget.clienteRepository),
      ),
    );
    if (mounted && selected != null) setState(() => _cliente = selected);
  }

  Future<void> _confirm(ConfirmarVentaCommand Function() command) async {
    if (_processing) return;
    final saleId = widget.saleId;
    if (saleId == null || widget.expectedDraftEventId == null) return;
    setState(() => _processing = true);
    try {
      await (widget.commandService ?? getIt<VentaCommandService>()).confirmar(
        command(),
      );
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => SaleReceiptScreen(saleId: saleId)),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _processing = false);
        if (_tab == _PaymentTab.cash) _focusCash();
      }
    }
  }

  void _confirmCash(int? receivedMinor) {
    if (_tab != _PaymentTab.cash) return;
    _confirm(
      () => ConfirmarVentaCommand(
        saleId: widget.saleId!,
        expectedDraftEventId: widget.expectedDraftEventId!,
        expectedTotalMinor: widget.totalMinor,
        receivedMinor: receivedMinor,
        clienteId: _cliente?.id,
      ),
    );
  }

  void _confirmTransfer(String reference) {
    if (_tab != _PaymentTab.transfer) return;
    _confirm(
      () => ConfirmarVentaCommand(
        saleId: widget.saleId!,
        expectedDraftEventId: widget.expectedDraftEventId!,
        expectedTotalMinor: widget.totalMinor,
        clienteId: _cliente?.id,
        paymentMethod: 'transfer',
        paymentReference: reference,
      ),
    );
  }

  Future<void> _confirmCredit() async {
    if (_processing || _tab != _PaymentTab.credit || !_canConfirmCredit) return;
    final cliente = _cliente!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar venta a crédito'),
        content: Text(
          'Se cargarán ${SaleDraftDisplay.money(widget.totalMinor)} a la cuenta de ${cliente.nombre}. No se recibe efectivo en esta operación.',
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
    await _confirm(
      () => ConfirmarVentaCommand(
        saleId: widget.saleId!,
        expectedDraftEventId: widget.expectedDraftEventId!,
        expectedTotalMinor: widget.totalMinor,
        clienteId: cliente.id,
        paymentMethod: 'credit',
      ),
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_processing,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Cobrar'),
        leading: BackButton(
          onPressed: _processing
              ? null
              : () => Navigator.of(context).maybePop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Total a cobrar: ${SaleDraftDisplay.money(widget.totalMinor)}',
                    key: const Key('payment_total'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF0F0F0),
      body: Focus(
        onKeyEvent: (_, event) =>
            _isEnterKey(event.logicalKey) &&
                (!_enterArmed || event is KeyRepeatEvent)
            ? KeyEventResult.handled
            : KeyEventResult.ignored,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PaymentMethodTabs(
                selected: _tab,
                enabled: !_processing,
                onSelected: _selectTab,
              ),
              _ClientSelector(
                cliente: _cliente,
                enabled: !_processing,
                onSelect: _selectCliente,
                onClear: () => setState(() => _cliente = null),
              ),
              Expanded(
                child: IndexedStack(
                  index: _tab.index,
                  children: [
                    Offstage(
                      offstage: _tab != _PaymentTab.cash,
                      child: CashPaymentContent(
                        key: _cashKey,
                        totalMinor: widget.totalMinor,
                        processing: _processing,
                        enabled: _canConfirmSale,
                        enterArmed: _enterArmed,
                        onConfirm: _confirmCash,
                      ),
                    ),
                    Offstage(
                      offstage: _tab != _PaymentTab.transfer,
                      child: TransferPaymentContent(
                        processing: _processing,
                        enabled: _canConfirmSale,
                        onConfirm: _confirmTransfer,
                      ),
                    ),
                    Offstage(
                      offstage: _tab != _PaymentTab.credit,
                      child: CreditPaymentContent(
                        cliente: _cliente,
                        processing: _processing,
                        enabled: _canConfirmCredit,
                        onConfirm: _confirmCredit,
                      ),
                    ),
                    Offstage(
                      offstage: _tab != _PaymentTab.card,
                      child: const CardPaymentContent(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

bool _isEnterKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter;

class _PaymentMethodTabs extends StatelessWidget {
  const _PaymentMethodTabs({
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final _PaymentTab selected;
  final bool enabled;
  final ValueChanged<_PaymentTab> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final buttons = [
          for (final tab in _PaymentTab.values)
            _PaymentTabButton(
              tab: tab,
              selected: tab == selected,
              enabled: enabled,
              onTap: () => onSelected(tab),
            ),
        ];
        if (constraints.maxWidth >= 440) {
          return Row(
            children: [
              for (final button in buttons)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: button,
                  ),
                ),
            ],
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final button in buttons)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(width: 120, child: button),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class _PaymentTabButton extends StatelessWidget {
  const _PaymentTabButton({
    required this.tab,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final _PaymentTab tab;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? scheme.primary : Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: Key('payment_tab_${tab.name}'),
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? scheme.onPrimary : scheme.onSurface,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClientSelector extends StatelessWidget {
  const _ClientSelector({
    required this.cliente,
    required this.enabled,
    required this.onSelect,
    required this.onClear,
  });

  final Cliente? cliente;
  final bool enabled;
  final VoidCallback onSelect;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    child: Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onSelect : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          child: Row(
            children: [
              const Icon(Icons.person_outline),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cliente?.nombre ?? 'Seleccionar cliente',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      cliente?.telefono ??
                          'Opcional para efectivo y transferencia · obligatorio para crédito',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: enabled ? onSelect : null,
                tooltip: 'Buscar cliente',
                icon: const Icon(Icons.search),
              ),
              if (cliente != null)
                IconButton(
                  onPressed: enabled ? onClear : null,
                  tooltip: 'Quitar cliente',
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
