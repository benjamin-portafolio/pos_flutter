import 'package:flutter/material.dart';
import '../../../domain/caja/cash_session.dart';
import '../finanzas/widgets/financial_delivery_status_chip.dart';
import 'cash_money.dart';

class CashSessionContent extends StatelessWidget {
  const CashSessionContent({super.key, required this.session});
  final CashSession session;
  @override
  Widget build(BuildContext context) {
    final s = session;
    final movements = s.closedMovements ?? s.movements;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          s.isClosed ? 'Caja cerrada' : 'Caja abierta',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text('Terminal: ${s.deviceId}'),
        Text(
          'Apertura: ${DateTime.fromMillisecondsSinceEpoch(s.openedAtMs)} · ${s.openedByUserId}',
        ),
        if (s.isClosed)
          Text(
            'Cierre: ${DateTime.fromMillisecondsSinceEpoch(s.closedAtMs!)} · ${s.closedByUserId}',
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: FinancialDeliveryStatusChip(
            status: s.deliveryStatus,
            rejectionReason: s.rejectionReason,
          ),
        ),
        if (s.rejectionReason != null)
          Text(
            s.rejectionReason!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            _total('Fondo inicial', BigInt.from(s.openingMinor)),
            _total('Entradas', s.incomeMinor),
            _total('Salidas', s.expenseMinor),
            _total('Efectivo esperado', s.expectedMinor),
            if (s.isClosed) ...[
              _total('Efectivo contado', BigInt.from(s.countedMinor!)),
              _total('Diferencia', s.differenceMinor!),
            ],
          ],
        ),
        if (s.notes != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('Nota: ${s.notes}'),
          ),
        const SizedBox(height: 20),
        Text(
          '${movements.length} movimientos${s.isClosed ? ' incluidos en el corte' : ''}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (movements.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Sin movimientos. El fondo inicial se cuenta una sola vez.',
            ),
          ),
        for (final m in movements)
          Card(
            child: ExpansionTile(
              title: Text(
                '${m.direction == 'in' ? 'Entrada' : 'Salida'} · ${switch (m.sourceType) {
                  'sale_payment' => 'Cobro de venta',
                  'customer_payment' => 'Abono de cliente',
                  'sale_adjustment' => 'Ajuste de venta',
                  'sale_reconciliation' => 'Conciliación de venta',
                  _ => 'Registro adicional',
                }}',
              ),
              subtitle: Text(
                '${cashMoney(BigInt.from(m.amountMinor))} · ${m.deliveryStatus == "not_required"
                    ? "Local"
                    : m.deliveryStatus == "delivered"
                    ? "Sincronizado"
                    : m.deliveryStatus == "pending"
                    ? "Pendiente"
                    : "Requiere atención"}',
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText('Origen: ${m.sourceId}'),
                      SelectableText('Evento: ${m.eventId}'),
                      SelectableText('Movimiento: ${m.id}'),
                      if (m.rejectionReason != null)
                        Text(
                          m.rejectionReason!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (s.regularizations.isNotEmpty) ...[
          const Text(
            'Conciliaciones independientes · conservan el corte original',
          ),
          for (final r in s.regularizations)
            ListTile(
              title: Text(
                '${r.isRecovery ? 'Recuperación posterior' : 'Reconocimiento de evidencia'} · ${cashMoney(BigInt.from(r.deltaMinor))}',
              ),
              subtitle: SelectableText(
                '${r.deliveryStatus} · Evento: ${r.eventId} · Efecto: ${r.effectId}',
              ),
            ),
        ],
        const Divider(),
        SelectableText('Sesión: ${s.id}'),
        SelectableText('Apertura: ${s.openingEventId}'),
        if (s.isClosed) SelectableText('Corte: ${s.lastEventId}'),
      ],
    );
  }

  Widget _total(String label, BigInt amount) => SizedBox(
    width: 200,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Text(
          cashMoney(amount),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}
