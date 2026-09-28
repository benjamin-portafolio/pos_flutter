import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../application/commands/caja/abrir_caja_command.dart';
import '../../../application/commands/caja/cerrar_caja_command.dart';
import '../../../application/commands/caja/caja_command_service.dart';
import '../../../core/di/injection.dart';
import '../../../domain/caja/cash_session.dart';
import '../../../domain/repositories/account_balance_baseline_repository.dart';
import '../../../domain/repositories/cash_repository.dart';
import '../../../domain/repositories/transfer_summary_repository.dart';
import 'cash_form_screen.dart';
import 'cash_detail_screen.dart';
import 'cash_session_content.dart';
import 'cash_money.dart';
import 'saldo_cuenta_estimado_card.dart';
import 'transfer_summary_card.dart';

class CashManagementScreen extends StatefulWidget {
  const CashManagementScreen({
    super.key,
    this.repository,
    this.commands,
    this.transfers,
    this.baselines,
  });
  final CashRepository? repository;
  final CajaCommandService? commands;

  /// Agregado de transferencias de la Fase 1. Se inyecta para poder probarlo
  /// sin levantar la base local; en la app sale del contenedor de DI.
  final TransferSummaryRepository? transfers;

  /// Lectura del saldo inicial declarado (Fase 3), para el bloque de saldo en
  /// cuenta. Igual que [transfers], se inyecta para poder probarlo.
  final AccountBalanceBaselineRepository? baselines;
  @override
  State<CashManagementScreen> createState() => _CashManagementScreenState();
}

class _CashManagementScreenState extends State<CashManagementScreen> {
  late final _repo = widget.repository ?? getIt<CashRepository>();
  late final _commands = widget.commands ?? getIt<CajaCommandService>();
  late final _transfers =
      widget.transfers ?? getIt<TransferSummaryRepository>();
  late final _baselines =
      widget.baselines ?? getIt<AccountBalanceBaselineRepository>();
  late final _sessions = _repo.watchSessions();
  bool _openingForm = false;
  Future<void> _form(CashSession? session) async {
    if (_openingForm) return;
    setState(() => _openingForm = true);
    final id = session?.id ?? const Uuid().v4();
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CashFormScreen(
          expectedMinor: session?.expectedMinor,
          onSave: (amount, notes) async {
            if (session == null) {
              await _commands.abrir(
                AbrirCajaCommand(sessionId: id, openingMinor: amount),
              );
            } else {
              await _commands.cerrar(
                CerrarCajaCommand(
                  sessionId: id,
                  countedMinor: amount,
                  notes: notes,
                ),
              );
            }
          },
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _openingForm = false);
    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            session == null ? 'Caja abierta.' : 'Corte guardado localmente.',
          ),
        ),
      );
    }
  }

  void _detail(CashSession s) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CashDetailScreen(sessionId: s.id, repository: _repo),
    ),
  );
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Caja'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Caja actual'),
            Tab(text: 'Historial de cortes'),
          ],
        ),
      ),
      body: StreamBuilder<List<CashSession>>(
        stream: _sessions,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('No se pudo consultar la caja.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data!,
              own = all
                  .where(
                    (s) =>
                        s.deviceId == _commands.context.deviceId && !s.isClosed,
                  )
                  .firstOrNull;
          return TabBarView(
            children: [
              ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  if (!_commands.enabled)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'La captura de caja no está habilitada en esta instalación.',
                        ),
                      ),
                    ),
                  if (own == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        'No hay caja abierta en esta terminal.',
                        style: TextStyle(fontSize: 22),
                      ),
                    )
                  else
                    CashSessionContent(session: own),
                  // Bloque 2. Va junto al de efectivo pero nunca se suma con
                  // él: uno es un stock y el otro un flujo (H7).
                  TransferSummaryCard(repository: _transfers, session: own),
                  // Bloque 3. El lado bancario como stock: saldo estimado y,
                  // solo con el saldo inicial declarado, el total en fondos.
                  SaldoCuentaEstimadoCard(
                    transfers: _transfers,
                    baselines: _baselines,
                    expectedMinor: own?.expectedMinor,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: !_commands.enabled || _openingForm
                        ? null
                        : () => _form(own),
                    icon: Icon(own == null ? Icons.point_of_sale : Icons.lock),
                    label: Text(own == null ? 'Abrir caja' : 'Hacer corte'),
                  ),
                  for (final s in all.where(
                    (s) =>
                        s.deviceId != _commands.context.deviceId && !s.isClosed,
                  ))
                    ListTile(
                      title: Text('Caja de ${s.deviceId}'),
                      subtitle: const Text('Consulta'),
                      trailing: Text(cashMoney(s.expectedMinor)),
                      onTap: () => _detail(s),
                    ),
                ],
              ),
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (!all.any((s) => s.isClosed))
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Todavía no hay cortes.'),
                    ),
                  for (final s in all.where((s) => s.isClosed))
                    Card(
                      child: ListTile(
                        title: Text(
                          '${DateTime.fromMillisecondsSinceEpoch(s.closedAtMs!)} · ${s.deviceId}',
                        ),
                        subtitle: Text(
                          'Diferencia: ${cashMoney(s.differenceMinor!)} · ${s.deliveryStatus == "not_required"
                              ? "Local"
                              : s.deliveryStatus == "delivered"
                              ? "Aceptado"
                              : s.deliveryStatus == "pending"
                              ? "Pendiente de aceptación"
                              : "Requiere atención"}${s.rejectionReason == null ? '' : ' · ${s.rejectionReason}'}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _detail(s),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );
}
