import 'movimiento_financiero_registrado_payload.dart';

/// Saldo inicial declarado de la cuenta bancaria única.
///
/// Hecho único e inmutable (D2), declarado una sola vez desde cualquier
/// terminal (D5) y sin sesión asociada (D3). No hay campo `cash`: no es un
/// movimiento de caja. No hay `previous_close_event_id`: no hay nada previo.
///
/// `amount_minor` ADMITE NEGATIVO a propósito. Una cuenta sobregirada es una
/// declaración legítima, y recortarla a cero corrompería el estimado en
/// silencio (R3). Es la única divergencia de rango frente al resto del
/// esquema, así que vive documentada aquí y en la Bitácora del plan.
///
/// `as_of_ms` es la FRONTERA: el saldo declarado cubre todo lo anterior a ese
/// instante. La Fase 4 suma solo los movimientos posteriores, para no contar
/// dos veces.
///
/// Espejo de `SaldoCuentaInicialDeclaradoPayload` de NestJS.
class SaldoCuentaInicialDeclaradoPayload {
  SaldoCuentaInicialDeclaradoPayload._({
    required this.amountMinor,
    required this.asOfMs,
  });

  static const aggregateType = 'account_balance_baseline';
  static const eventType = 'saldo_cuenta_inicial_declarado';

  /// Slot único GLOBAL. El `refId` es una constante, no el `deviceId`: el
  /// saldo se declara una sola vez en la instalación, sin importar quién lo
  /// declare. No se agrega `account_id` (fuera de alcance, R4).
  static const slotRefType = 'account_balance_slot';
  static const slotRefId = 'unica';

  final int amountMinor;
  final int asOfMs;

  /// No hay nada previo: el hecho no depende de ningún otro evento.
  List<String> get dependencyEventIds => const [];

  factory SaldoCuentaInicialDeclaradoPayload.fromJson(Map<String, Object?> p) =>
      SaldoCuentaInicialDeclaradoPayload._(
        amountMinor: bankBalanceMinor(p['amount_minor']),
        asOfMs: financialOccurredAtMs(p['as_of_ms']),
      );

  Map<String, Object?> toJson() => {
    'amount_minor': amountMinor,
    'as_of_ms': asOfMs,
  };
}

/// Saldo en centavos con signo, rango simétrico al entero seguro.
///
/// Es el validador de `cashNonnegative` con el rango abierto hacia abajo, y a
/// propósito: la cuenta puede estar sobregirada. Mismo techo que
/// `financialAmountMinor` (`maxAmountMinor`), que es el límite de
/// `Number.MAX_SAFE_INTEGER` en el servidor.
int bankBalanceMinor(Object? value) {
  if (value is! int || value < -maxAmountMinor || value > maxAmountMinor) {
    throw const FormatException(
      'amount_minor debe ser un entero en centavos dentro del rango seguro.',
    );
  }
  return value;
}
