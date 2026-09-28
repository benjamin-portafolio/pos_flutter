/// Formato exacto en centavos, también para totales mayores al entero seguro.
String cashMoney(BigInt value) {
  final absolute = value.abs(), hundred = BigInt.from(100);
  return '${value.isNegative ? '-' : ''}\$${absolute ~/ hundred}.${(absolute % hundred).toString().padLeft(2, '0')}';
}

int? parseCashMoney(String value) {
  final m = RegExp(r'^(\d{1,15})(?:\.(\d{1,2}))?$').firstMatch(value.trim());
  if (m == null) return null;
  final minor =
      BigInt.parse(m.group(1)!) * BigInt.from(100) +
      BigInt.parse((m.group(2) ?? '0').padRight(2, '0'));
  return minor > BigInt.from(9007199254740991) ? null : minor.toInt();
}

/// Importe con signo en centavos. A diferencia de [parseCashMoney], acepta
/// negativo: el saldo de una cuenta sobregirada es una declaracion legitima y
/// recortarlo a cero corromperia el estimado en silencio. Es el parser de la
/// declaracion (Fase 3) y de la conciliacion contra el estado de cuenta
/// (Fase 4), un solo parser con signo en vez de dos.
int? parseSignedMoney(String value) {
  final m = RegExp(
    r'^(-)?(\d{1,15})(?:\.(\d{1,2}))?$',
  ).firstMatch(value.trim());
  if (m == null) return null;
  final cents =
      BigInt.parse(m.group(2)!) * BigInt.from(100) +
      BigInt.parse((m.group(3) ?? '0').padRight(2, '0'));
  final signed = m.group(1) == null ? cents : -cents;
  return signed.abs() > BigInt.from(9007199254740991) ? null : signed.toInt();
}
