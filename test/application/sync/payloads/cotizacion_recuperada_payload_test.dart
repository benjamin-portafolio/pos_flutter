import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/cotizaciones/recuperar_cotizacion_command.dart';
import 'package:pos_flutter/application/commands/cotizaciones/quotation_recovery_identity.dart';
import 'package:pos_flutter/application/sync/payloads/cotizacion_recuperada_payload.dart';
import '../../../support/quotation_contract_fixtures.dart';

void main() {
  final fixture = quotationFixture('recuperacion-vinculo-v2');
  final event = fixture['event'] as Map;
  Map<String, Object?> valid() =>
      copyQuotationJson(event['payload'] as Map<String, Object?>);
  test('P03/P12: roundtrip formato 2, mapa y refs del fixture', () {
    final p = CotizacionRecuperadaPayload.fromJson(valid());
    p.validateIdentity(event['event_id'] as String);
    expect(p.toJson(), valid());
    expect(p.draftVersion, 2);
    expect(
      p
          .refs(event['aggregate_id'] as String)
          .map((r) => '${r.refType}:${r.relationship}'),
      ['quotation:affects', 'sale:uses', 'event:uses', 'event:uses'],
    );
    expect(() => p.lines.clear(), throwsUnsupportedError);
    expect(() => p.refs(''), throwsFormatException);
    expect(() => p.refs(p.saleId), throwsFormatException);
    expect(
      () => p.validateIdentity('20000000-0000-4000-8000-000000000090'),
      throwsFormatException,
    );
  });
  test(
    'P03: legado, nulos ausentes y datos monetarios nunca son compatibles',
    () {
      final old = quotationFixture('recuperacion-antigua-incompatible');
      final p = old;
      expect(
        () => CotizacionRecuperadaPayload.fromJson(p),
        throwsFormatException,
      );
      expect(
        () => CotizacionRecuperadaPayload.fromJson({...p, 'format_version': 2}),
        throwsFormatException,
      );
      for (final field in valid().keys) {
        final j = valid()..remove(field);
        expect(
          () => CotizacionRecuperadaPayload.fromJson(j),
          throwsFormatException,
          reason: field,
        );
      }
      for (final field in [
        'total_minor',
        'currency',
        'snapshot',
        'unit_price_minor',
        'catalog_unit_price_minor',
        'consumption_configuration_key',
        'hidden',
      ]) {
        final j = valid()..[field] = {'price': 123};
        expect(
          () => CotizacionRecuperadaPayload.fromJson(j),
          throwsFormatException,
        );
        final nested = valid();
        ((nested['lines'] as List).first as Map)[field] = 123;
        expect(
          () => CotizacionRecuperadaPayload.fromJson(nested),
          throwsFormatException,
        );
      }
    },
  );
  test('P12: mapa completo ordenado, UUIDs y metadatos redundantes', () {
    for (final edit in [
      <String, Object?>{'format_version': 2.0},
      {'draft_version': 1},
      {'draft_created_event_id': 'other'},
      {'draft_last_event_id': 'other'},
      {'sale_id': ''},
      {'previous_sale_id': ''},
      {'recovered_at_ms': 0},
      {'recovered_at_ms': 1791310200001},
      {'lines': []},
    ]) {
      expect(
        () => CotizacionRecuperadaPayload.fromJson({...valid(), ...edit}),
        throwsFormatException,
      );
    }
    for (final edit in [
      <String, Object?>{'quotation_item_id': ''},
      {'sale_item_id': 'other'},
      {'draft_event_id': 'other'},
      {'sort_order': -1},
      {'sort_order': 1.0},
    ]) {
      final j = valid();
      ((j['lines'] as List).first as Map).addAll(edit);
      expect(
        () => CotizacionRecuperadaPayload.fromJson(j),
        throwsFormatException,
      );
    }
    final j = valid();
    (j['lines'] as List)[1] = (j['lines'] as List)[0];
    expect(
      () => CotizacionRecuperadaPayload.fromJson(j),
      throwsFormatException,
    );
  });
  test('P12/P14: identidades fijadas en fase 1 e intención reconstruida', () {
    final p = CotizacionRecuperadaPayload.fromJson(valid());
    for (final l in p.lines) {
      expect(
        QuotationRecoveryIdentity.saleItem(p.saleId, l.quotationItemId),
        l.saleItemId,
      );
      expect(
        QuotationRecoveryIdentity.draftEvent(
          event['event_id'] as String,
          p.saleId,
          l.quotationItemId,
        ),
        l.draftEventId,
      );
    }
    final c = RecuperarCotizacionCommand(
      quotationId: ' q ',
      expectedQuotationEventId: ' rev ',
      recoveredAtLocal: DateTime.utc(2026, 1, 1, 0, 0, 0, 999),
    );
    final retry = RecuperarCotizacionCommand(
      quotationId: c.quotationId,
      expectedQuotationEventId: c.expectedQuotationEventId,
      saleId: c.saleId,
      eventId: c.eventId,
      recoveredAtLocal: c.recoveredAtLocal,
    );
    expect(c.quotationId, 'q');
    expect(c.expectedQuotationEventId, 'rev');
    expect(c.recoveredAtLocal, DateTime.utc(2026));
    expect(retry.eventId, c.eventId);
    expect(retry.saleId, c.saleId);
    expect(
      QuotationRecoveryIdentity.saleItem(c.saleId, 'line'),
      QuotationRecoveryIdentity.saleItem(retry.saleId, 'line'),
    );
    expect(
      QuotationRecoveryIdentity.draftEvent(c.eventId, c.saleId, 'line'),
      isNot(QuotationRecoveryIdentity.draftEvent('other', c.saleId, 'line')),
    );
  });
}
