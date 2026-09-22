import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../../../application/commands/creditos/credito_command_service.dart';
import '../../../application/commands/creditos/registrar_abono_command.dart';
import '../../../core/di/injection.dart';
import '../../../domain/clientes/cliente.dart';

class RegistrarAbonoScreen extends StatefulWidget {
  const RegistrarAbonoScreen({
    required this.cliente,
    this.commandService,
    super.key,
  });
  final Cliente cliente;
  final CreditoCommandService? commandService;
  @override
  State<RegistrarAbonoScreen> createState() => _RegistrarAbonoScreenState();
}

class _RegistrarAbonoScreenState extends State<RegistrarAbonoScreen> {
  final _id = const Uuid().v4();
  final _amount = TextEditingController(), _reference = TextEditingController();
  String _method = 'cash';
  bool _saving = false;
  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final input = _amount.text.trim().replaceAll(',', '.');
      if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(input)) {
        throw const FormatException(
          'Introduce un importe con hasta dos decimales.',
        );
      }
      final parts = input.split('.');
      final minor =
          BigInt.parse(parts[0]) * BigInt.from(100) +
          BigInt.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
      if (minor <= BigInt.zero || minor > BigInt.from(9007199254740991)) {
        throw const FormatException('Importe fuera de rango.');
      }
      await (widget.commandService ?? getIt<CreditoCommandService>())
          .registrarAbono(
            RegistrarAbonoCommand(
              id: _id,
              clienteId: widget.cliente.id,
              amountMinor: minor.toInt(),
              method: _method,
              reference: _reference.text,
            ),
          );
      if (mounted) Navigator.pop(context, _id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('Registrar abono')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.cliente.nombre,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 20),
          TextField(
            key: const Key('abono_importe'),
            controller: _amount,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Importe recibido (MXN)',
              prefixText: '\$ ',
            ),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: const InputDecoration(labelText: 'Método'),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
              DropdownMenuItem(value: 'transfer', child: Text('Transferencia')),
            ],
            onChanged: _saving ? null : (v) => setState(() => _method = v!),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _reference,
            enabled: !_saving,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Referencia o nota (opcional)',
            ),
          ),
          const Text(
            'Se aplicará a las ventas más antiguas. El sobrante quedará como saldo a favor.',
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Guardando…' : 'Guardar abono'),
          ),
        ],
      ),
    ),
  );
}
