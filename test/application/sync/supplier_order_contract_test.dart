import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/supplier_order_json.dart';
import 'package:pos_flutter/application/sync/payloads/supplier_order_draft_saved_payload.dart';
import 'package:pos_flutter/application/sync/payloads/supplier_order_confirmed_payload.dart';
import 'package:pos_flutter/application/sync/payloads/supplier_receipt_confirmed_payload.dart';
import 'package:pos_flutter/application/sync/payloads/supplier_order_cancelled_payload.dart';
import 'package:pos_flutter/application/sync/payloads/supplier_order_closed_payload.dart';
import 'package:pos_flutter/application/sync/payloads/supplier_replenishment_patch.dart';

void main() {
  final fixtures =
      jsonDecode(
            File(
              'test/fixtures/supplier_orders_v1/contracts.json',
            ).readAsStringSync(),
          )
          as Map;
  for (final f in fixtures['documents'] as List) {
    test(f['name'] as String, () {
      Map<String, Object?> parse() => switch (f['kind']) {
        'draft' => SupplierOrderDraftSavedPayload.fromJson(
          f['payload'],
        ).toJson(),
        'confirmed' => SupplierOrderConfirmedPayload.fromJson(
          f['payload'],
        ).toJson(),
        'receipt' => SupplierReceiptConfirmedPayload.fromJson(
          f['payload'],
        ).toJson(),
        'cancelled' => SupplierOrderCancelledPayload.fromJson(
          f['payload'],
        ).toJson(),
        'closed' => SupplierOrderClosedPayload.fromJson(f['payload']).toJson(),
        _ => throw StateError('fixture'),
      };
      if (f['valid'] == true) {
        expect(parse(), f['payload']);
      } else {
        expect(parse, throwsFormatException);
      }
    });
  }
  for (final f in fixtures['patches'] as List) {
    test(f['name'] as String, () {
      Map<String, Object?> parse() =>
          SupplierReplenishmentPatch.fromJson(f['payload']).toJson();
      if (f['valid'] == true) {
        expect(parse(), f['payload']);
      } else {
        expect(parse, throwsFormatException);
      }
    });
  }
  for (final f in fixtures['money'] as List) {
    test(
      'redondeo $f',
      () => expect(
        orderAmount(
          f['price'] as int,
          f['quantity'] as int,
          f['reference'] as int,
        ),
        f['total'],
      ),
    );
  }
  test('overflow y payload acotado', () {
    expect(() => orderAmount(9007199254740991, 2, 1), throwsFormatException);
    expect(() => orderTotal([9007199254740991, 1]), throwsFormatException);
    expect(() => orderPayloadSize({'x': 'á' * 50000}), throwsFormatException);
  });
}
