import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/presentation/pages/gestion_clientes/models/cliente_resumen_display.dart';

void main() {
  group('ClienteResumenDisplay.money', () {
    test('formatea MXN con decimales y signo', () {
      expect(ClienteResumenDisplay.money(BigInt.from(-15000)), r'-$150.00');
      expect(ClienteResumenDisplay.money(BigInt.from(3500)), r'$35.00');
      expect(ClienteResumenDisplay.money(BigInt.zero), r'$0.00');
    });
  });

  group('ClienteResumenDisplay.ultimoMovimientoLabel', () {
    final now = DateTime(2026, 9, 24, 10, 30);

    test('sin movimientos', () {
      expect(ClienteResumenDisplay.ultimoMovimientoLabel(null), 'Sin movimientos');
    });

    test('hoy', () {
      expect(
        ClienteResumenDisplay.ultimoMovimientoLabel(
          DateTime(2026, 9, 24, 8, 0),
          now: now,
        ),
        'Último movimiento: hoy',
      );
    });

    test('hace 1 día', () {
      expect(
        ClienteResumenDisplay.ultimoMovimientoLabel(
          DateTime(2026, 9, 23, 8, 0),
          now: now,
        ),
        'Último movimiento: hace 1 día',
      );
    });

    test('hace 5 días', () {
      expect(
        ClienteResumenDisplay.ultimoMovimientoLabel(
          DateTime(2026, 9, 19, 8, 0),
          now: now,
        ),
        'Último movimiento: hace 5 días',
      );
    });

    test('fechas futuras por desfase de reloj se muestran como hoy', () {
      expect(
        ClienteResumenDisplay.ultimoMovimientoLabel(
          DateTime(2026, 9, 26, 8, 0),
          now: now,
        ),
        'Último movimiento: hoy',
      );
    });
  });

  group('ClienteResumenDisplay.estadoDeCuenta', () {
    test('adeudo en rojo con importe', () {
      final estado = ClienteResumenDisplay.estadoDeCuenta(BigInt.from(-15000));
      expect(estado.label, 'Debe \$150.00');
      expect(estado.estado, SaldoEstado.adeudo);
      expect(
        ClienteResumenDisplay.colorDe(
          estado.estado,
          ThemeData(),
        ),
        ThemeData().colorScheme.error,
      );
    });

    test('saldo a favor en verde con importe', () {
      final estado = ClienteResumenDisplay.estadoDeCuenta(BigInt.from(3500));
      expect(estado.label, 'Saldo a favor \$35.00');
      expect(estado.estado, SaldoEstado.aFavor);
    });

    test('cero es Sin adeudo', () {
      final estado = ClienteResumenDisplay.estadoDeCuenta(BigInt.zero);
      expect(estado.label, 'Sin adeudo');
      expect(estado.estado, SaldoEstado.sinAdeudo);
    });
  });
}