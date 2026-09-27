import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/movimiento_financiero_registrado_payload.dart';
import 'package:pos_flutter/domain/finanzas/financial_direction.dart';
import 'package:pos_flutter/domain/finanzas/financial_nature.dart';

import '../../../fixtures/financial_fixture_loader.dart';

const _maxAmountMinor = 9007199254740991;

void main() {
  test('parsea un registro cash canónico', () {
    final json = readFinancialFixture('registro/entry-renta-cash-valid.json');
    final parsed = MovimientoFinancieroRegistradoPayload.fromJson(json);

    expect(parsed.categoryId, '11111111-1111-4111-8111-111111111111');
    expect(parsed.categoryEventId, '22222222-2222-4222-8222-222222222222');
    expect(parsed.categoryNameSnapshot, 'Renta');
    expect(parsed.direction, FinancialDirection.expense);
    expect(parsed.nature, FinancialNature.operating);
    expect(parsed.amountMinor, 50000);
    expect(parsed.currency, 'MXN');
    expect(parsed.method, 'cash');
    expect(parsed.occurredAtMs, 1789041600000);
    expect(parsed.notes, 'Renta en efectivo');
    expect(parsed.reference, isNull);
    expect(parsed.toJson(), json);
  });

  test('parsea transfer con referencia y registro de ingreso', () {
    final transfer = MovimientoFinancieroRegistradoPayload.fromJson(
      readFinancialFixture('registro/entry-renta-transfer-valid.json'),
    );
    expect(transfer.method, 'transfer');
    expect(transfer.amountMinor, 150000);
    expect(transfer.reference, 'SPEI-2026-09-20');
    expect(
      transfer.toJson(),
      readFinancialFixture('registro/entry-renta-transfer-valid.json'),
    );

    final ingreso = MovimientoFinancieroRegistradoPayload.fromJson(
      readFinancialFixture('registro/entry-ingreso-cash-valid.json'),
    );
    expect(ingreso.direction, FinancialDirection.income);
    expect(ingreso.categoryId, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    expect(ingreso.categoryEventId, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
    expect(ingreso.amountMinor, 200000);
  });

  test('normaliza notas/referencia vacías o de solo espacios a null', () {
    final nulas = MovimientoFinancieroRegistradoPayload.fromJson(
      readFinancialFixture('registro/entry-null-notes-reference-valid.json'),
    );
    final vacias = MovimientoFinancieroRegistradoPayload.fromJson(
      readFinancialFixture('registro/entry-referencia-vacia-valid.json'),
    );
    final espacios = MovimientoFinancieroRegistradoPayload.fromJson(
      readFinancialFixture('registro/entry-referencia-espacios-valid.json'),
    );

    expect(nulas.notes, isNull);
    expect(nulas.reference, isNull);
    expect(vacias.notes, isNull);
    expect(vacias.reference, isNull);
    expect(espacios.notes, 'Renta en efectivo');
    expect(espacios.reference, isNull);
  });

  test('acepta 500 code points en notas y el mayor importe seguro', () {
    final notas = MovimientoFinancieroRegistradoPayload.fromJson(
      readFinancialFixture('registro/entry-notas-500-valid.json'),
    );
    expect(notas.notes!.runes.length, 500);

    final maximo = MovimientoFinancieroRegistradoPayload.fromJson(
      readFinancialFixture('registro/entry-monto-maximo-valid.json'),
    );
    expect(maximo.amountMinor, _maxAmountMinor);
  });

  for (final testCase in [
    (
      'entry-notas-501-invalid.json',
      'notes debe tener entre 1 y 500 caracteres.',
    ),
    (
      'entry-monto-cero-invalid.json',
      'amount_minor debe ser un entero positivo en centavos.',
    ),
    (
      'entry-monto-negativo-invalid.json',
      'amount_minor debe ser un entero positivo en centavos.',
    ),
    (
      'entry-monto-fraccionario-invalid.json',
      'amount_minor debe ser un entero positivo en centavos.',
    ),
    (
      'entry-monto-superior-invalid.json',
      'amount_minor debe ser un entero positivo en centavos.',
    ),
    ('entry-moneda-invalid.json', 'Moneda inválida.'),
    ('entry-metodo-invalid.json', 'method debe ser cash o transfer.'),
    (
      'entry-occurred-cero-invalid.json',
      'occurred_at_ms debe ser un instante válido.',
    ),
    ('entry-category-id-invalid.json', 'category_id debe ser un UUID v4.'),
  ]) {
    test('${testCase.$1} se rechaza con error canónico', () {
      expect(
        () => MovimientoFinancieroRegistradoPayload.fromJson(
          readFinancialFixture('registro/${testCase.$1}'),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            testCase.$2,
          ),
        ),
      );
    });
  }

  test(
    'acepta dirección/naturaleza que solo difieren de la categoría '
    '(decisiones del handler)',
    () {
      for (final file in [
        'registro/entry-direction-snapshot-invalid.json',
        'registro/entry-nature-snapshot-invalid.json',
        'registro/entry-dependencia-inexistente.json',
      ]) {
        expect(
          () => MovimientoFinancieroRegistradoPayload.fromJson(
            readFinancialFixture(file),
          ),
          returnsNormally,
        );
      }
    },
  );
}