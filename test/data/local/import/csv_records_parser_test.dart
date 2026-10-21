import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/import/csv_records_parser.dart';

void main() {
  const parser = CsvRecordsParser();
  for (final separator in [',', ';']) {
    test('conserva campos vacíos y separadores citados $separator', () {
      expect(
        parser.parse('""$separator"a,b;c"$separator', separator: separator),
        [
          ['', 'a,b;c', ''],
        ],
      );
      expect(parser.parse('""', separator: separator), [
        [''],
      ]);
      expect(parser.parse(separator, separator: separator), [
        ['', ''],
      ]);
      expect(parser.parse('  \n\r\n', separator: separator), isEmpty);
    });
    test('conserva saltos dentro de comillas $separator', () {
      expect(
        parser.parse('"a\r\nb\nc"$separator"d""e"\r\n', separator: separator),
        [
          ['a\r\nb\nc', 'd"e'],
        ],
      );
    });
    for (final invalid in [
      '"sin cerrar',
      'texto"citado"',
      '"cerrado"extra',
      '"cerrado""',
    ]) {
      test('rechaza sintaxis inválida $separator $invalid', () {
        expect(
          () => parser.parse(invalid, separator: separator),
          throwsFormatException,
        );
      });
    }
  }
}
