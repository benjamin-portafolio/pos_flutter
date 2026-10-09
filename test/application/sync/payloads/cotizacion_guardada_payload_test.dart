import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/cotizacion_guardada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/quotation_selection_snapshot.dart';
import '../../../support/quotation_contract_fixtures.dart';

void main() {
  Map<String, Object?> valid() => quotationFixture('seleccion-sin-precios');
  test('P01/P03: roundtrip del fixture fase 1 y refs de guardado', () {
    final p = CotizacionGuardadaPayload.fromJson(valid());
    expect(p.toJson(), valid());
    expect(p.lines.last.selection.measuredQuantityAtomic, 500);
    expect(p.refs('20000000-0000-4000-8000-000000000001').length, 4);
    expect(() => p.lines.clear(), throwsUnsupportedError);
    expect(() => p.refs(''), throwsFormatException);
    expect(() => p.refs(p.sourceSaleId), throwsFormatException);
    expect(() => p.refs('other'), throwsFormatException);
    final json = p.lines.first.selection.toJson();
    json['product_name_snapshot'] = ' Pan ';
    json['variant_name_snapshot'] = ' ';
    final selection = QuotationSelectionSnapshot.fromJson(json);
    expect(selection.productName, 'Pan');
    expect(selection.variantName, isNull);
  });
  test(
    'P03: formato anterior, etiquetado como 2 y copias monetarias anidadas rechazados',
    () {
      final old = quotationFixture('guardado-antiguo-incompatible');
      final payload = old;
      expect(
        () => CotizacionGuardadaPayload.fromJson(payload),
        throwsFormatException,
      );
      expect(
        () => CotizacionGuardadaPayload.fromJson({
          ...payload,
          'format_version': 2,
        }),
        throwsFormatException,
      );
      for (final field in [
        'unit_price_minor',
        'standard_cost_minor_snapshot',
        'total_minor',
        'price_reference_quantity_atomic_snapshot',
        'consumption_configuration_key',
        'snapshot',
        'hidden',
      ]) {
        for (final level in [0, 1, 2]) {
          final j = copyQuotationJson(valid());
          final line = (j['lines'] as List).first as Map;
          final target = level == 0
              ? j
              : level == 1
              ? line
              : line['selection'] as Map;
          target[field] = {'price': 123};
          expect(
            () => CotizacionGuardadaPayload.fromJson(j),
            throwsFormatException,
            reason: '$level/$field',
          );
        }
      }
    },
  );
  test('P01/P03: tipos, rangos, nulos explícitos, unidades y orden', () {
    final mutations = <void Function(Map<String, Object?>)>[
      (j) => j.remove('format_version'),
      (j) => j['format_version'] = 1,
      (j) => j['format_version'] = 2.0,
      (j) => j['source_sale_id'] = ' ',
      (j) => j['issued_at_ms'] = 0,
      (j) => j['issued_at_ms'] = 1791309600001,
      (j) => j['lines'] = [],
      (j) => (j['lines'] as List).add((j['lines'] as List).first),
      (j) => (j['lines'] as List).sort(
        (a, b) => (b['sort_order'] as int).compareTo(a['sort_order'] as int),
      ),
      (j) => ((j['lines'] as List).first as Map)['sort_order'] = -1,
      (j) =>
          ((j['lines'] as List).first as Map)['sort_order'] = 9007199254740992,
    ];
    for (final mutate in mutations) {
      final j = copyQuotationJson(valid());
      mutate(j);
      expect(
        () => CotizacionGuardadaPayload.fromJson(j),
        throwsFormatException,
      );
    }
    for (final number in [0, -1, 9007199254740992, 1.0, '2', true, null]) {
      final j = copyQuotationJson(valid());
      (((j['lines'] as List).first as Map)['selection'] as Map)['quantity'] =
          number;
      expect(
        () => CotizacionGuardadaPayload.fromJson(j),
        throwsFormatException,
      );
    }
    for (final field in QuotationSelectionSnapshot.fields) {
      final j = copyQuotationJson(valid());
      (((j['lines'] as List).first as Map)['selection'] as Map).remove(field);
      expect(
        () => CotizacionGuardadaPayload.fromJson(j),
        throwsFormatException,
      );
    }
    for (final edit in [
      {'quantity': 1},
      {'sale_unit_atomic_factor_snapshot': 0},
      {'sale_unit_symbol_snapshot': ''},
      {'sale_mode_snapshot': 'unit'},
      {'measured_quantity_atomic': null},
    ]) {
      final j = copyQuotationJson(valid());
      (((j['lines'] as List).last as Map)['selection'] as Map).addAll(edit);
      expect(
        () => CotizacionGuardadaPayload.fromJson(j),
        throwsFormatException,
      );
    }
    final j = copyQuotationJson(valid());
    (((j['lines'] as List).first as Map)['selection'] as Map)['quantity'] =
        9007199254740991;
    expect(
      CotizacionGuardadaPayload.fromJson(j).lines.first.selection.quantity,
      9007199254740991,
    );
  });
}
