import 'financial_direction.dart';

/// Origen del dinero de una transferencia. Los códigos coinciden con la
/// columna `origin` del shape normalizado (`money_movements_sql.dart`), para
/// que la etiqueta de la UI y el dato persistido no puedan divergir.
enum TransferOrigin {
  sale('sale', 'Venta'),
  customerPayment('customer_payment', 'Abono de cliente'),
  financialEntry('financial_entry', 'Movimiento financiero');

  const TransferOrigin(this.code, this.label);

  /// Código persistido en la columna `origin`.
  final String code;

  /// Etiqueta visible para la UI.
  final String label;

  static TransferOrigin fromCode(String code) {
    return TransferOrigin.values.firstWhere(
      (value) => value.code == code,
      orElse: () => throw const FormatException(
        'origin debe ser sale, customer_payment o financial_entry.',
      ),
    );
  }
}

/// Una transferencia ya normalizada, con su signo resuelto (H4).
///
/// [amountMinor] es siempre positivo: las tres tablas lo guardan así y el signo
/// va aparte. Para venta por transferencia el CHECK de la tabla ya obliga a
/// `received_minor = amount_minor` y `change_minor = 0`, así que [amountMinor]
/// es el importe recibido; el cambio no se suma.
class TransferMovement {
  const TransferMovement({
    required this.id,
    required this.eventId,
    required this.origin,
    required this.method,
    required this.amountMinor,
    required this.occurredAtMs,
    required this.direction,
    this.reference,
  });

  final String id, eventId, method;
  final String? reference;
  final TransferOrigin origin;

  /// Importe positivo en centavos, tal como se guardó.
  final int amountMinor;

  /// Instante efectivo en ms UTC. En ventas por transferencia es la fecha del
  /// evento que la confirmó, no la del cobro (H1b).
  final int occurredAtMs;

  /// `in` solo puede venir de `financial_entries`; los otros dos orígenes
  /// siempre reciben.
  final FinancialDirection direction;

  /// Importe con signo: `+` si la plata entra, `−` si sale. Es la única fuente
  /// del signo, para que nunca se calcule dos veces.
  BigInt get signedAmountMinor => direction == FinancialDirection.income
      ? BigInt.from(amountMinor)
      : -BigInt.from(amountMinor);
}

/// Agregado de transferencias de un periodo `[fromMs, toMs)`, sobre los tres
/// origenes de dinero: ventas, abonos de cliente y movimientos financieros.
///
/// Todos los totales son `BigInt`, nunca `int`. Es dinero registrado por
/// transferencia, no un saldo bancario, no utilidad y no dinero en el cajón.
class TransferSummary {
  const TransferSummary({
    required this.fromMs,
    required this.toMs,
    required this.movements,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.netMinor,
    required this.byOrigin,
  });

  /// Suma los movimientos ya filtrados por periodo y método. El repositorio
  /// entrega la lista; el agregado se calcula aquí con `BigInt` para que ningún
  /// total dependa del ancho de `int`.
  factory TransferSummary.fromMovements({
    required int fromMs,
    required int toMs,
    required List<TransferMovement> movements,
  }) {
    var income = BigInt.zero;
    var expense = BigInt.zero;
    final byOrigin = <TransferOrigin, BigInt>{};
    for (final movement in movements) {
      final amount = BigInt.from(movement.amountMinor);
      if (movement.direction == FinancialDirection.income) {
        income += amount;
      } else {
        expense += amount;
      }
      byOrigin.update(
        movement.origin,
        (value) => value + movement.signedAmountMinor,
        ifAbsent: () => movement.signedAmountMinor,
      );
    }
    return TransferSummary(
      fromMs: fromMs,
      toMs: toMs,
      movements: List.unmodifiable(movements),
      incomeMinor: income,
      expenseMinor: expense,
      netMinor: income - expense,
      byOrigin: Map.unmodifiable(byOrigin),
    );
  }

  /// Inicio del periodo, inclusivo.
  final int fromMs;

  /// Fin del periodo, exclusivo.
  final int toMs;

  /// Movimientos del periodo, del más reciente al más antiguo.
  final List<TransferMovement> movements;

  /// Entradas por transferencia. Siempre `>= 0`.
  final BigInt incomeMinor;

  /// Salidas por transferencia. Siempre `>= 0`.
  final BigInt expenseMinor;

  /// Entradas menos salidas. Puede ser negativo.
  final BigInt netMinor;

  /// Neto con signo por origen, solo con los orígenes presentes en el periodo.
  final Map<TransferOrigin, BigInt> byOrigin;

  bool get isEmpty => movements.isEmpty;

  /// Neto de un origen; `BigInt.zero` si ese origen no se movió en el periodo.
  BigInt netForOrigin(TransferOrigin origin) =>
      byOrigin[origin] ?? BigInt.zero;
}
