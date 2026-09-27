import 'package:flutter/material.dart';

import '../customer_account_display.dart';

/// Tipo de saldo de un cliente para pintar el estado de cuenta.
enum SaldoEstado { adeudo, aFavor, sinAdeudo }

/// Formato de los datos visibles en la tarjeta de cliente.
///
/// Lógica pura de presentación: importes MXN, etiqueta de último movimiento y
/// estado de cuenta con su tipo de saldo.
class ClienteResumenDisplay {
  /// MXN en centavos con signo: `-$150.00`, `$35.00`.
  static String money(BigInt value) => CustomerAccountDisplay.money(value);

  /// Texto del último movimiento: `Sin movimientos` o
  /// `Último movimiento: hoy` / `: hace 5 días`.
  static String ultimoMovimientoLabel(DateTime? ultimo, {DateTime? now}) {
    if (ultimo == null) return 'Sin movimientos';
    return 'Último movimiento: ${ultimoMovimiento(ultimo, now: now)}';
  }

  /// Parte relativa del último movimiento por día local: `hoy` o `hace N días`.
  static String ultimoMovimiento(DateTime ultimo, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final day = DateTime(ultimo.year, ultimo.month, ultimo.day);
    final days = today.difference(day).inDays;
    if (days <= 0) return 'hoy';
    if (days == 1) return 'hace 1 día';
    return 'hace $days días';
  }

  /// Estado de cuenta: adeudo en rojo, saldo a favor en verde y "Sin adeudo"
  /// cuando el saldo es cero. El importe acompaña al texto.
  static ({String label, SaldoEstado estado}) estadoDeCuenta(
    BigInt saldo,
  ) {
    if (saldo.isNegative) {
      return (label: 'Debe ${money(saldo.abs())}', estado: SaldoEstado.adeudo);
    }
    if (saldo > BigInt.zero) {
      return (
        label: 'Saldo a favor ${money(saldo)}',
        estado: SaldoEstado.aFavor,
      );
    }
    return (label: 'Sin adeudo', estado: SaldoEstado.sinAdeudo);
  }

  /// Color del estado de cuenta según el tipo de saldo y el tema actual.
  static Color colorDe(SaldoEstado estado, ThemeData theme) => switch (estado) {
    SaldoEstado.adeudo => theme.colorScheme.error,
    SaldoEstado.aFavor => const Color(0xFF2E7D32),
    SaldoEstado.sinAdeudo => theme.colorScheme.onSurfaceVariant,
  };
}