import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/categoria_financiera_creada_payload.dart';
import 'package:pos_flutter/domain/finanzas/financial_direction.dart';
import 'package:pos_flutter/domain/finanzas/financial_nature.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../../../fixtures/financial_fixture_loader.dart';

void main() {
  for (final testCase in [
    ('payload-renta-valid.json', 'Renta', 'out', 'operating'),
    ('payload-aportacion-valid.json', 'Aportaciones', 'in', 'capital'),
    ('payload-nombre-100-valid.json', 'C' * 100, 'out', 'operating'),
  ]) {
    test('${testCase.$1} se parsea y serializa canónicamente', () {
      final parsed = CategoriaFinancieraCreadaPayload.fromJson(
        readFinancialFixture('categoria_financiera/${testCase.$1}'),
      );

      expect(parsed.name, testCase.$2);
      expect(parsed.direction, FinancialDirection.fromCode(testCase.$3));
      expect(parsed.nature, FinancialNature.fromCode(testCase.$4));
      expect(parsed.toJson(), {
        'name': testCase.$2,
        'direction': testCase.$3,
        'nature': testCase.$4,
      });
    });
  }

  test('normaliza NFKC+trim antes de validar longitud', () {
    final json = readFinancialFixture(
      'categoria_financiera/payload-renta-nfkc-valid.json',
    );
    final rawName = json['name']! as String;
    final parsed = CategoriaFinancieraCreadaPayload.fromJson(json);

    expect(parsed.name, unorm.nfkc(rawName).trim());
    expect(parsed.name.runes.any((r) => r >= 0x300 && r <= 0x36f), isFalse);
  });

  for (final testCase in [
    (
      'payload-nombre-101-invalid.json',
      'name debe tener entre 1 y 100 caracteres.',
    ),
    (
      'payload-nombre-vacio-invalid.json',
      'El nombre de la categoría financiera es obligatorio.',
    ),
    (
      'payload-nombre-no-string-invalid.json',
      'El nombre de la categoría financiera es obligatorio.',
    ),
    ('payload-direction-invalid.json', 'direction debe ser in u out.'),
    ('payload-direction-ausente-invalid.json', 'direction debe ser in u out.'),
    ('payload-nature-invalid.json', 'nature no está permitida.'),
    (
      'payload-nature-incompatible-invalid.json',
      'nature no es compatible con la dirección.',
    ),
  ]) {
    test('${testCase.$1} se rechaza con error canónico', () {
      expect(
        () => CategoriaFinancieraCreadaPayload.fromJson(
          readFinancialFixture('categoria_financiera/${testCase.$1}'),
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

  test('sobre con aggregate_type ajeno no engaña al payload (contrato §6.1)', () {
    final sobre = readFinancialFixture(
      'categoria_financiera/sobre-aggregate-type-invalid.json',
    );
    final payload = (sobre['payload']! as Map).cast<String, Object?>();

    expect(() => CategoriaFinancieraCreadaPayload.fromJson(payload),
        returnsNormally);
    expect(sobre['aggregate_type'],
        isNot(CategoriaFinancieraCreadaPayload.aggregateType));
  });
}