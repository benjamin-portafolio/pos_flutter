/// Formato monetario de centavos a pesos MXN, con soporte de signo.
///
/// Compartido por las tarjetas y pantallas de informes para que el importe de
/// "Ventas totales", el beneficio bruto y el desglose por método usen la misma
/// representación. Los cálculos monetarios siempre usan enteros o `BigInt`.
class ReportMoney {
  const ReportMoney._();

  /// Formatea centavos como `$X.YY MXN`. No admite importes negativos.
  static String money(BigInt cents) {
    final hundred = BigInt.from(100);
    final whole = cents ~/ hundred;
    final centsPart = (cents % hundred).toString().padLeft(2, '0');
    final sign = cents.isNegative ? '-' : '';
    return '$sign\$$whole.$centsPart MXN';
  }

  /// Formatea centavos con signo: `$X.YY MXN` o `-$X.YY MXN`.
  static String signedMoney(BigInt cents) {
    if (!cents.isNegative) return money(cents);
    final abs = BigInt.zero - cents;
    return '-${money(abs)}';
  }

  /// Fracción decimal de [part] sobre [total], en 0..100.
  /// Devuelve 0 cuando [total] es cero para no dividir entre cero.
  static double percentOf(BigInt part, BigInt total) => total == BigInt.zero
      ? 0
      : (part * BigInt.from(10000)) ~/ total / BigInt.from(100);
}