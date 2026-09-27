import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/presentation/pages/finanzas/models/money_input.dart';

void main() {
  group('MoneyInput.parseMinor', () {
    test('pesos a centavos enteros sin double', () {
      expect(MoneyInput.parseMinor('1234'), 123400);
      expect(MoneyInput.parseMinor('1234.5'), 123450);
      expect(MoneyInput.parseMinor('1234.56'), 123456);
      expect(MoneyInput.parseMinor('0.01'), 1);
      expect(MoneyInput.parseMinor('  7  '), 700);
    });

    test('rechaza vacío, cero, negativo, no numérico y exceso de decimales', () {
      for (final invalido in [
        '',
        '   ',
        '0',
        '0.00',
        '-5',
        '-5.50',
        'abc',
        '1,5',
        '1.234',
        '1.2.3',
        '12a',
      ]) {
        expect(MoneyInput.parseMinor(invalido), isNull, reason: invalido);
      }
    });

    test('rechaza fuera del entero seguro del contrato', () {
      expect(MoneyInput.parseMinor('90071992547409.92'), isNull);
      expect(MoneyInput.parseMinor('90071992547409.91'), 9007199254740991);
      expect(MoneyInput.parseMinor('123456789012345.00'), isNull);
    });
  });
}