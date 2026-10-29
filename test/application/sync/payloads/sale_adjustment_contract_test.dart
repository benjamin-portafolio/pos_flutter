import 'dart:convert';
import 'dart:io';
import 'package:pos_flutter/application/commands/ventas/sale_adjustment_command_contract.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/payloads/venta_confirmada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/sale_adjustment_payload.dart';
import 'package:pos_flutter/application/sync/payloads/venta_anulada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/devolucion_venta_registrada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/sale_adjustment_rules.dart';
import 'package:pos_flutter/application/sync/payloads/sale_adjustment_delivery_policy.dart';
import 'package:pos_flutter/application/sync/payloads/operacion_venta_conciliada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/sale_reconciliation_effect.dart';
import 'package:pos_flutter/domain/ventas/sale_adjustment_credit_rules.dart';

Map<String, Object?> map(Object? value) =>
    Map<String, Object?>.from(value as Map);
void main() {
  final file = File('contracts/sale_adjustments/v1.json');
  final f = jsonDecode(file.readAsStringSync()) as Map;
  test('shared fixture digest (Dart and TypeScript pin the same bytes)', () {
    expect(
      sha256.convert(file.readAsBytesSync()).toString(),
      '494a26a085fa980dfeeb4e6279c4cb9b1a5007f99f65a0c4170f164ec77252e2',
    );
  });
  for (final raw in f['arithmetic'] as List) {
    final v = raw as Map;
    test('cumulative ${v['total']} ${v['before']}→${v['after']}', () {
      expect(
        SaleAdjustmentRules.cumulative(
              v['total'] as int,
              v['after'] as int,
              v['original'] as int,
            ) -
            SaleAdjustmentRules.cumulative(
              v['total'] as int,
              v['before'] as int,
              v['original'] as int,
            ),
        v['expected'],
      );
    });
  }
  for (final raw in f['cases'] as List) {
    final c = raw as Map;
    for (final mode in ['standalone', 'server_sync']) {
      test('$mode ${c['name']}', () {
        void run() {
          final original = VentaConfirmadaPayload.fromJson(map(c['original']));
          final j = map(c['payload']);
          final p = j['kind'] == 'void'
              ? VentaAnuladaPayload.fromJson(j).adjustment
              : DevolucionVentaRegistradaPayload.fromJson(j).adjustment;
          final history = (c['history'] as List)
              .map((v) => SaleAdjustmentPayload.fromJson(map(v)))
              .toList();
          SaleAdjustmentRules.validate(
            p,
            original,
            confirmationEventId: '00000000-0000-4000-8000-000000000014',
            saleId: '00000000-0000-4000-8000-000000000001',
            history: history,
          );
          if (c['cash_context'] != null) {
            final cash = c['cash_context'] as Map;
            SaleAdjustmentRules.validateCash(
              p,
              enabled: cash['enabled'] as bool,
              open: cash['open'] as bool,
              sessionId: cash['session_id'] as String?,
              openingEventId: cash['opening_event_id'] as String?,
            );
          }
          if (c['expected_money'] != null) {
            expect(
              SaleAdjustmentRules.paidMoneyEffects(p),
              c['expected_money'],
            );
            expect(
              p.settlement.cash!.sessionId,
              isNot((c['closed_cut'] as Map)['session_id']),
            );
          }
          expect(p.toJson(), j);
          final refs = SaleAdjustmentRules.refs(p, original);
          expect(
            refs.any(
              (r) =>
                  r.refType == 'sale' &&
                  r.refId == p.saleId &&
                  r.relationship == 'affects',
            ),
            isTrue,
          );
          expect(
            refs
                .map((r) => '${r.refType}/${r.refId}/${r.relationship}')
                .toList()
              ..sort(),
            c['expected_refs'],
          );
          final entry = SaleAdjustmentCommandContract.prepare(
            payload: p,
            original: original,
            saleId: p.saleId,
            confirmationEventId: p.confirmationEventId,
            history: history,
            mode: mode,
            userId: 'operator',
            deviceId: 'terminal',
            integrationVerified: true,
          );
          expect(
            entry.event.deliveryStatus,
            mode == 'standalone' ? 'not_required' : 'pending',
          );
          expect(entry.event.baseVersion, p.expectedRevision + 1);
          expect(entry.refs.length, refs.length);
          expect(
            SaleAdjustmentDeliveryPolicy.forMode(
              mode,
              integrationVerified: true,
            ),
            {
              'delivery_status': mode == 'standalone'
                  ? 'not_required'
                  : 'pending',
              'persist_refs': mode == 'server_sync',
            },
          );
        }

        if (c['valid'] == true) {
          run();
        } else {
          expect(run, throwsA(anything));
        }
      });
    }
  }
  for (final raw in f['fifo'] as List) {
    final c = raw as Map;
    test(c['name'] as String, () {
      Map<String, Object?> run() => SaleAdjustmentCreditRules.allocate(
        (c['charges'] as List)
            .map(
              (v) => (
                id: v['id'] as String,
                occurredAtMs: v['occurredAtMs'] as int,
                amountMinor: v['amountMinor'] as int,
                reductionMinor: v['reductionMinor'] as int,
              ),
            )
            .toList(),
        (c['payments'] as List)
            .map(
              (v) => (
                id: v['id'] as String,
                occurredAtMs: v['occurredAtMs'] as int,
                amountMinor: v['amountMinor'] as int,
              ),
            )
            .toList(),
      );
      if (c['valid'] == false) {
        expect(run, throwsA(anything));
      } else {
        expect(run(), c['expected']);
      }
    });
  }
  for (final raw in f['reconciliations'] as List) {
    final c = raw as Map;
    test(c['name'] as String, () {
      void run() {
        final p = OperacionVentaConciliadaPayload.fromJson(map(c['payload']));
        final evidence = (f['reconciliation_evidence'] as List)
            .map(SaleReconciliationEffect.fromJson)
            .toList();
        final canonical =
            (f['reconciliations'] as List).first['payload'] as Map;
        p.validateIncident(
          incident: canonical['incident_id'] as String,
          sale: canonical['sale_id'] as String,
          loser: canonical['loser_event_id'] as String,
          winner: canonical['winner_event_id'] as String,
          officialBase: canonical['official_base_event_id'] as String,
          revision: 1,
          evidence: evidence,
          alreadyConsumed: false,
        );
        expect(p.toJson(), c['payload']);
        expect(p.refs.any((r) => r.refType == 'sale_incident'), isTrue);
        expect(
          () => p.validateIncident(
            incident: p.incidentId,
            sale: p.saleId,
            loser: p.loserEventId,
            winner: p.winnerEventId,
            officialBase: p.officialBaseEventId,
            revision: 1,
            evidence: evidence,
            alreadyConsumed: true,
          ),
          throwsFormatException,
        );
      }

      if (c['valid'] == true) {
        run();
      } else {
        expect(run, throwsA(anything));
      }
    });
  }
  test(
    'stable identity matches after transport metadata changes, rejects business change',
    () {
      final c = (f['cases'] as List).first as Map;
      final p = SaleAdjustmentPayload.fromJson(map(c['payload']));
      final original = VentaConfirmadaPayload.fromJson(map(c['original']));
      final a = SaleAdjustmentCommandContract.prepare(
        payload: p,
        original: original,
        saleId: p.saleId,
        confirmationEventId: p.confirmationEventId,
        history: [],
        mode: 'standalone',
        userId: 'operator',
        deviceId: 'terminal',
      ).event;
      expect(
        SaleAdjustmentCommandContract.sameIntention(
          a,
          a.copyWith(
            serverSequence: 99,
            baseServerSequence: 71,
            deliveryStatus: 'delivered',
          ),
        ),
        isTrue,
      );
      expect(
        SaleAdjustmentCommandContract.sameIntention(
          a,
          a.copyWith(payload: {...a.payload, 'reason': 'Otra intención'}),
        ),
        isFalse,
      );
      expect(
        SaleAdjustmentCommandContract.sameIntention(
          a,
          a.copyWith(userId: 'other'),
        ),
        isFalse,
      );
      expect(
        () => SaleAdjustmentCommandContract.prepare(
          payload: p,
          original: original,
          saleId: p.saleId,
          confirmationEventId: p.confirmationEventId,
          history: [],
          mode: 'server_sync',
          userId: 'operator',
          deviceId: 'terminal',
        ),
        throwsStateError,
      );
    },
  );
  test('normalization and event family are explicit', () {
    final c = (f['cases'] as List).first as Map;
    final j = map(c['payload']);
    final p = VentaAnuladaPayload.fromJson({
      ...j,
      'reason': '  Corrección documentada  ',
    });
    expect(p.adjustment.reason, 'Corrección documentada');
    expect(
      () => DevolucionVentaRegistradaPayload.fromJson(j),
      throwsFormatException,
    );
    expect(
      () => VentaAnuladaPayload.fromJson({...j, 'schema_version': 2}),
      throwsFormatException,
    );
  });
  test('temporary gate, standalone is independent of server readiness', () {
    expect(
      SaleAdjustmentDeliveryPolicy.forMode(
        'standalone',
        integrationVerified: false,
      )['delivery_status'],
      'not_required',
    );
    expect(
      () => SaleAdjustmentDeliveryPolicy.forMode(
        'server_sync',
        integrationVerified: false,
      ),
      throwsStateError,
    );
  });
  test('effective accepted base; pending dependencies; terminal incidence', () {
    expect(
      SaleAdjustmentDeliveryPolicy.resolveBase(
        'base',
        ['confirmation'],
        {
          'base': {'status': 'accepted', 'server_sequence': 71},
          'confirmation': {'status': 'accepted', 'server_sequence': 12},
        },
      ),
      {'status': 'ready', 'base_server_sequence': 71},
    );
    expect(
      SaleAdjustmentDeliveryPolicy.resolveBase(
        'base',
        ['confirmation'],
        {
          'base': {'status': 'pending'},
          'confirmation': {'status': 'accepted', 'server_sequence': 12},
        },
      )['status'],
      'pending',
    );
    expect(
      SaleAdjustmentDeliveryPolicy.resolveBase('base', [], {})['status'],
      'pending',
    );
    for (final status in ['rejected', 'conflict', 'not_required']) {
      expect(
        SaleAdjustmentDeliveryPolicy.resolveBase('base', [], {
          'base': {'status': status},
        })['status'],
        'incident',
      );
    }
  });
}
