import 'dart:convert';
import 'cash_movement_evidence.dart';
import 'caja_abierta_payload.dart';
import 'categoria_financiera_creada_payload.dart';
import 'inventory_movement_payload.dart';
import 'movimiento_financiero_registrado_payload.dart';

class CajaCerradaPayload {
  CajaCerradaPayload({
    required this.openingEventId,
    required this.closedAtMs,
    required this.countedMinor,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.expectedMinor,
    required this.differenceMinor,
    required List<CashMovementEvidence> movements,
    String? notes,
  }) : movements = List.unmodifiable(
         [...movements]..sort((a, b) => a.movementId.compareTo(b.movementId)),
       ),
       notes = financialOptionalText(notes, 'notes', 500) {
    InventoryMovementPayload.requiredUuidV4(openingEventId, 'opening_event_id');
    financialOccurredAtMs(closedAtMs);
    cashNonnegative(countedMinor);
    for (final v in [
      incomeMinor,
      expenseMinor,
      expectedMinor,
      differenceMinor,
    ]) {
      if (v.length > 100 || !RegExp(r'^(0|-?[1-9][0-9]*)$').hasMatch(v)) {
        throw const FormatException('Total decimal inválido.');
      }
    }
    if (movements.map((m) => m.movementId).toSet().length != movements.length ||
        movements.map((m) => m.eventId).toSet().length != movements.length) {
      throw const FormatException('Movimientos duplicados en corte.');
    }
  }
  static const aggregateType = 'cash_session', eventType = 'caja_cerrada';
  final String openingEventId,
      incomeMinor,
      expenseMinor,
      expectedMinor,
      differenceMinor;
  final String? notes;
  final int closedAtMs, countedMinor;
  final List<CashMovementEvidence> movements;
  List<String> get dependencyEventIds => [
    openingEventId,
    ...movements.map((m) => m.eventId),
  ];
  factory CajaCerradaPayload.fromJson(Map<String, Object?> p) =>
      CajaCerradaPayload(
        openingEventId: p['opening_event_id'] as String,
        closedAtMs: p['closed_at_ms'] as int,
        countedMinor: p['counted_minor'] as int,
        incomeMinor: p['income_minor'] as String,
        expenseMinor: p['expense_minor'] as String,
        expectedMinor: p['expected_minor'] as String,
        differenceMinor: p['difference_minor'] as String,
        notes: p['notes'] as String?,
        movements: (p['movements'] as List)
            .map(
              (m) => CashMovementEvidence.fromJson(
                Map<String, Object?>.from(m as Map),
              ),
            )
            .toList(),
      );
  void verify(int opening, List<CashMovementEvidence> actual) {
    final sorted = [...actual]
      ..sort((a, b) => a.movementId.compareTo(b.movementId));
    final incoming = actual
        .where((m) => m.direction == 'in')
        .fold(BigInt.zero, (s, m) => s + BigInt.from(m.amountMinor));
    final outgoing = actual
        .where((m) => m.direction == 'out')
        .fold(BigInt.zero, (s, m) => s + BigInt.from(m.amountMinor));
    final expected = BigInt.from(opening) + incoming - outgoing;
    if (jsonEncode(sorted.map((m) => m.toJson()).toList()) !=
            jsonEncode(movements.map((m) => m.toJson()).toList()) ||
        incomeMinor != incoming.toString() ||
        expenseMinor != outgoing.toString() ||
        expectedMinor != expected.toString() ||
        differenceMinor != (BigInt.from(countedMinor) - expected).toString()) {
      throw StateError('El conjunto o los totales del corte no coinciden.');
    }
  }

  Map<String, Object?> toJson() => {
    'opening_event_id': openingEventId,
    'closed_at_ms': closedAtMs,
    'counted_minor': countedMinor,
    'income_minor': incomeMinor,
    'expense_minor': expenseMinor,
    'expected_minor': expectedMinor,
    'difference_minor': differenceMinor,
    'notes': notes,
    'movements': movements.map((m) => m.toJson()).toList(),
  };
}
