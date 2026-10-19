import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/articulos/importe_comercial_codec.dart';

void main() {
  const codec = ImporteComercialCodec();

  test('M04: variantes decimales equivalen sin redondear ni usar float', () {
    for (final value in ['20', '20.0', '20,00', ' 020.00 ']) {
      expect(codec.parse(value, admiteCero: false), 2000);
    }
    expect(
      codec.parse('90071992547409.91', admiteCero: false),
      9007199254740991,
    );
    for (final value in [
      '',
      ' ',
      '-1',
      '+1',
      '1e2',
      '1.234',
      '20,000',
      '1,000.00',
      '90071992547409.92',
      '184467440737095516.17',
      '9999999999999999999999999999999999999999999999999999',
    ]) {
      expect(
        () => codec.parse(value, admiteCero: true),
        throwsFormatException,
        reason: value,
      );
    }
  });

  test('M05: cero explícito solo se permite para costo', () {
    expect(codec.parse('0,00', admiteCero: true), 0);
    expect(() => codec.parse('0', admiteCero: false), throwsFormatException);
  });
}
