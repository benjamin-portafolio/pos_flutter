import 'cash_movement.dart';

class CashSession {
  CashSession({
    required this.id,
    required this.deviceId,
    required this.openedByUserId,
    required this.status,
    required this.openedAtMs,
    required this.openingMinor,
    required this.openingEventId,
    required this.lastEventId,
    required this.deliveryStatus,
    required this.movements,
    this.closedByUserId,
    this.closedAtMs,
    this.countedMinor,
    this.notes,
    this.rejectionReason,
    this.closedIncomeMinor,
    this.closedExpenseMinor,
    this.closedExpectedMinor,
    this.closedDifferenceMinor,
  });
  final String id,
      deviceId,
      openedByUserId,
      status,
      openingEventId,
      lastEventId,
      deliveryStatus;
  final String? closedByUserId, notes, rejectionReason;
  final int openedAtMs, openingMinor;
  final int? closedAtMs, countedMinor;
  final List<CashMovement> movements;
  final BigInt? closedIncomeMinor,
      closedExpenseMinor,
      closedExpectedMinor,
      closedDifferenceMinor;
  bool get isClosed => status == 'closed';
  BigInt get incomeMinor =>
      closedIncomeMinor ??
      movements
          .where((m) => m.direction == 'in')
          .fold(BigInt.zero, (s, m) => s + BigInt.from(m.amountMinor));
  BigInt get expenseMinor =>
      closedExpenseMinor ??
      movements
          .where((m) => m.direction == 'out')
          .fold(BigInt.zero, (s, m) => s + BigInt.from(m.amountMinor));
  BigInt get expectedMinor =>
      closedExpectedMinor ??
      BigInt.from(openingMinor) + incomeMinor - expenseMinor;
  BigInt? get differenceMinor => closedDifferenceMinor;
}
