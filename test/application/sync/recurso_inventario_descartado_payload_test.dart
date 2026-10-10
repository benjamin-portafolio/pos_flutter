import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/recurso_inventario_creado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/recurso_inventario_descartado_payload.dart';

import '../../fixtures/variant_tracking_fixture_loader.dart';

void main() {
  group('RecursoInventarioDescartadoPayload', () {
    test('declara el agregado y la política admitida', () {
      expect(
        RecursoInventarioDescartadoPayload.aggregateType,
        'inventory_item',
      );
      expect(
        RecursoInventarioDescartadoPayload.eventType,
        'recurso_inventario_descartado',
      );
      expect(RecursoInventarioDescartadoPayload.supportedPolicyVersion, 1);
      // Invariante de modo: el descarte nunca viaja al servidor.
      expect(RecursoInventarioDescartadoPayload.deliveryStatus, 'not_required');
    });

    test('lee y reemite el descarte válido', () {
      final payload = fixturePayload('descarte/descarte-valido.json');
      final parsed = RecursoInventarioDescartadoPayload.fromJson(payload);

      expect(parsed.baseEventId, 'b1000000-0000-4000-8000-000000000001');
      expect(parsed.triggerProductId, 'a1000000-0000-4000-8000-000000000001');
      expect(
        parsed.triggerProductEventId,
        'b3000000-0000-4000-8000-000000000003',
      );
      expect(parsed.originVariantId, 'a2000000-0000-4000-8000-000000000001');
      expect(parsed.policyVersion, 1);
      expect(parsed.toJson(), payload);
    });

    test('acepta el sobre completo con el agregado siendo el recurso', () {
      final sobre = readVariantTrackingFixture(
        'descarte/sobre-descarte-valido.json',
      );
      expect(sobre['aggregate_type'], 'inventory_item');
      expect(sobre['aggregate_id'], 'a3000000-0000-4000-8000-000000000001');
      expect(sobre['event_type'], 'recurso_inventario_descartado');
      expect(
        RecursoInventarioDescartadoPayload.fromJson(
          sobre['payload']! as Map<String, Object?>,
        ).policyVersion,
        1,
      );
    });

    test('no incluye inventory_item_id en el payload', () {
      // El agregado ya es el recurso: incluir su id sería redundancia que puede
      // contradecir al sobre.
      expect(fixturePayload('descarte/descarte-valido.json').keys.toSet(), {
        'base_event_id',
        'trigger_product_id',
        'trigger_product_event_id',
        'origin_variant_id',
        'policy_version',
      });
    });

    test('rechaza campos desconocidos', () {
      expect(
        () => RecursoInventarioDescartadoPayload.fromJson(
          fixturePayload('descarte/descarte-campo-desconocido.json'),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('campos no permitidos: force'),
          ),
        ),
      );
    });

    for (final fixture in [
      'descarte/descarte-policy-version-cero.json',
      'descarte/descarte-policy-version-invalida.json',
    ]) {
      test('rechaza policy_version distinta de 1 en $fixture', () {
        expect(
          () => RecursoInventarioDescartadoPayload.fromJson(
            fixturePayload(fixture),
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('policy_version solo admite 1'),
            ),
          ),
        );
      });
    }

    for (final field in [
      'policy_version',
      'base_event_id',
      'trigger_product_id',
      'trigger_product_event_id',
      'origin_variant_id',
    ]) {
      test('exige $field', () {
        final payload = fixturePayload('descarte/descarte-valido.json')
          ..remove(field);
        expect(
          () => RecursoInventarioDescartadoPayload.fromJson(payload),
          throwsA(isA<FormatException>()),
        );
      });
    }

    test('rechaza que el disparador sea el alta del recurso', () {
      expect(
        () => RecursoInventarioDescartadoPayload.fromJson(
          fixturePayload('descarte/descarte-trigger-igual-base.json'),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('no puede ser el alta del recurso'),
          ),
        ),
      );
    });

    test('rechaza procedencia no v4', () {
      expect(
        () => RecursoInventarioDescartadoPayload.fromJson(
          fixturePayload('descarte/descarte-origen-no-uuid.json'),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('UUID v4'),
          ),
        ),
      );
    });

    test('declara referencias de entrega por variante y producto', () {
      final parsed = RecursoInventarioDescartadoPayload.fromJson(
        fixturePayload('descarte/descarte-valido.json'),
      );

      final refs = parsed.refs('a3000000-0000-4000-8000-000000000001');
      expect(
        refs
            .map((ref) => '${ref.refType}:${ref.refId}:${ref.relationship}')
            .toSet(),
        {
          'inventory_item:a3000000-0000-4000-8000-000000000001:affects',
          'product:a1000000-0000-4000-8000-000000000001:uses',
          'product_variant:a2000000-0000-4000-8000-000000000001:uses',
        },
      );
    });

    test('rechaza un recurso no identificable al declarar referencias', () {
      final parsed = RecursoInventarioDescartadoPayload.fromJson(
        fixturePayload('descarte/descarte-valido.json'),
      );

      expect(
        () => parsed.refs('recurso-250g'),
        throwsA(isA<FormatException>()),
      );
    });

    test('el origen del descarte usa la clave compartida con el alta', () {
      // Una sola clave para el mismo concepto en ambos contratos.
      expect(
        RecursoInventarioDescartadoPayload.fromJson(
          fixturePayload('descarte/descarte-valido.json'),
        ).toJson()[RecursoInventarioCreadoPayload.originVariantIdField],
        'a2000000-0000-4000-8000-000000000001',
      );
    });
  });
}

Map<String, Object?> fixturePayload(String relativePath) =>
    readVariantTrackingFixture(relativePath)['payload']!
        as Map<String, Object?>;
