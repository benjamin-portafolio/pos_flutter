import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../application/commands/cuenta/cuenta_command_service.dart';
import '../../../application/commands/cuenta/declarar_saldo_cuenta_inicial_command.dart';
import '../../../core/di/injection.dart';
import '../../../domain/cuenta/account_balance_baseline.dart';
import '../../../domain/repositories/account_balance_baseline_repository.dart';
import '../caja/cash_money.dart';
import '../finanzas/widgets/financial_delivery_status_chip.dart';

/// Pantalla de declaración del saldo inicial de la cuenta bancaria.
///
/// Es una pantalla propia y no parte de la de caja: el saldo en cuenta no es
/// efectivo, no abre ni cierra sesión, y declararlo no suma nada al cajón.
/// Muestra el hecho declarado con su chip de entrega y, mientras no exista, la
/// forma de declararlo una vez.
///
/// El total estimado NO se calcula aquí. Esta fase solo guarda y sincroniza el
/// hecho; la suma con los movimientos posteriores es de la Fase 4.
class DeclararSaldoCuentaScreen extends StatefulWidget {
  const DeclararSaldoCuentaScreen({
    super.key,
    this.repository,
    this.commands,
  });

  /// Se inyectan para poder probarlos sin levantar la base local; en la app
  /// salen del contenedor de DI.
  final AccountBalanceBaselineRepository? repository;
  final CuentaCommandService? commands;

  @override
  State<DeclararSaldoCuentaScreen> createState() =>
      _DeclararSaldoCuentaScreenState();
}

class _DeclararSaldoCuentaScreenState
    extends State<DeclararSaldoCuentaScreen> {
  late final _repo =
      widget.repository ?? getIt<AccountBalanceBaselineRepository>();
  late final _commands = widget.commands ?? getIt<CuentaCommandService>();
  late final _baseline = _repo.watchBaseline();
  bool _saving = false;
  String? _error;

  Future<void> _declarar(int amountMinor) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _commands.declarar(
        DeclararSaldoCuentaInicialCommand(
          baselineId: const Uuid().v4(),
          amountMinor: amountMinor,
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is StateError
              ? error.message
              : 'No se pudo declarar el saldo: $error';
        });
      }
      return;
    }
    if (!mounted) return;
    // Sin aviso extra: el hecho recien declarado aparece en su card con el
    // chip de entrega, y ahi se ve que sigue pendiente de aceptacion.
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Saldo en cuenta')),
    body: StreamBuilder<AccountBalanceBaseline?>(
      stream: _baseline,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('No se pudo consultar el saldo.'));
        }
        // El stream emite `null` cuando todavia no hay hecho declarado, asi que
        // `hasData` no sirve para saber si la consulta respondio: se pregunta
        // por la conexion, no por el dato.
        if (snapshot.connectionState == ConnectionState.none) {
          return const Center(child: CircularProgressIndicator());
        }
        final baseline = snapshot.data;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (!_commands.enabled)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'El saldo en cuenta no está habilitado en esta instalación.',
                  ),
                ),
              ),
            if (baseline != null) ...[
              _BaselineCard(baseline: baseline),
              const SizedBox(height: 16),
              // El hecho es inmutable: aquí no hay nada que editar ni borrar.
              // Un saldo mal capturado se corrige con un ajuste posterior, no
              // con una segunda declaración.
              const Text(
                'Este saldo se declara una sola vez y no se modifica. Si el '
                'importe estaba mal, se corrige con un movimiento posterior, no '
                'declarando otro saldo.',
                style: TextStyle(fontSize: 13),
              ),
            ] else
              _DeclarationForm(enabled: _commands.enabled, onDeclare: _declarar),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            const Text(
              'El saldo declarado es un hecho único. No es efectivo de cajón y '
              'no se suma al corte de caja.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        );
      },
    ),
  );
}

class _BaselineCard extends StatelessWidget {
  const _BaselineCard({required this.baseline});

  final AccountBalanceBaseline baseline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('declared_baseline_card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saldo declarado', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              // El saldo puede ser negativo: la cuenta puede estar sobregirada
              // y recortarlo a cero falsearía el estimado.
              _signed(baseline.amountMinor),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Cubre todo lo anterior al '
              '${_stamp(baseline.asOfMs)}.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            // El chip es el de finanzas, el mismo que muestra caja: el estado de
            // entrega se lee igual en todos los hechos.
            FinancialDeliveryStatusChip(
              status: baseline.deliveryStatus,
              rejectionReason: baseline.rejectionReason,
            ),
            const SizedBox(height: 4),
            Text(
              'Declarado por ${baseline.deviceId} · '
              '${baseline.declaredByUserId}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _DeclarationForm extends StatefulWidget {
  const _DeclarationForm({required this.enabled, required this.onDeclare});

  final bool enabled;
  final Future<void> Function(int amountMinor) onDeclare;

  @override
  State<_DeclarationForm> createState() => _DeclarationFormState();
}

class _DeclarationFormState extends State<_DeclarationForm> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || !_form.currentState!.validate()) return;
    final parsed = parseSignedMoney(_amount.text)!;
    setState(() => _saving = true);
    await widget.onDeclare(parsed);
    if (!mounted) return;
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final preview = parseSignedMoney(_amount.text);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Todavía no se declara el saldo de la cuenta bancaria.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'Captura lo que el banco reporta ahora. Es el punto de partida '
                'del estimado y se declara una sola vez.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('bank_amount'),
                controller: _amount,
                enabled: widget.enabled && !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Saldo reportado por el banco (MXN)',
                  hintText: '0.00',
                  helperText: 'Un saldo negativo es válido: la cuenta puede '
                      'estar sobregirada.',
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) => parseSignedMoney(v ?? '') == null
                    ? 'Captura un importe válido.'
                    : null,
              ),
              if (preview != null) ...[
                const SizedBox(height: 12),
                Text('Se declarará: $_signed(preview)'),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('bank_declare'),
                onPressed: !widget.enabled || _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.account_balance),
                label: Text(_saving ? 'Declarando…' : 'Declarar saldo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _stamp(int ms) =>
    '${DateTime.fromMillisecondsSinceEpoch(ms).toLocal()}';

String _signed(int minor) {
  final cents = minor.abs();
  final whole = cents ~/ 100;
  final rest = (cents % 100).toString().padLeft(2, '0');
  return '${minor < 0 ? '-' : ''}\$$whole.$rest';
}
