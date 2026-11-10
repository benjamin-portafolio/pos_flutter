import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/recovery/recovery_cancellation.dart';
import 'package:pos_flutter/application/recovery/recovery_reconciliation_validator.dart';
import 'package:pos_flutter/data/local/recovery/drift_recovery_snapshot_source.dart';
import '../../../application/commands/ventas/sale_reconciliation_test.dart'
    show ReconciliationHarness;

void main() {
  test(
    'conciliación entregada: valida efectos y exporta una vez; alteración bloquea',
    () async {
      final x = await ReconciliationHarness.create();
      addTearDown(x.h.close);
      final p = await x.payload();
      await x.submit(p);
      await x.accept(p);
      // Evidencia remota sintética explícita; el harness original no acredita
      // admisibilidad global (catálogo y saldo inicial sin todos sus creadores).
      await x.h.db.customStatement(
        'UPDATE events SET server_sequence=8 WHERE event_id=?',
        [p.loserEventId],
      );
      await x.h.db.customStatement(
        'UPDATE events SET created_at_server=1794153600',
      );
      await x.h.db.customStatement(
        'UPDATE inventory_balances SET last_event_id=?,last_server_sequence=8 WHERE inventory_item_id=?',
        [p.loserEventId, x.resourceId],
      );
      final source = DriftRecoverySnapshotSource(x.h.db);
      final s = await source.capture(
        privateDirectory: x.h.directory,
        mode: AppMode.serverSync,
        deviceId: 'fixture',
        appRevision: 's3-test',
        cancellation: RecoveryCancellation(),
      );
      addTearDown(s.close);
      final incident = s.rows('sale_delivery_incidents').single;
      RecoveryReconciliationValidator.validateIncident(s, incident);
      final effects = s.exportRows('sale_reconciliation_effects').toList();
      final physicalIds = effects.map((r) => r['effect_id']).toSet();
      expect(
        s
            .exportRows('inventory_movements')
            .any((m) => physicalIds.contains(m['movement_id'])),
        false,
      );
      expect(
        s
            .exportRows('cash_movements')
            .any((m) => physicalIds.contains(m['id'])),
        false,
      );
      expect(s.exportRows('sale_adjustments').length, 1);
      expect(s.exportRows('sale_adjustment_evidence').length, 1);
      final balance = s
          .exportRows('inventory_balances')
          .singleWhere((b) => b['inventory_item_id'] == x.resourceId);
      expect(balance['last_event_id'], p.eventId);
      expect(balance['last_server_sequence'], '3');
      final trace = s.exportRows('projection_provenance').single;
      expect((trace['source_row'] as Map)['last_event_id'], p.loserEventId);
      expect(await source.hasChangesSince(s), false);
      await x.h.db.customStatement(
        'UPDATE sale_reconciliation_effects SET delta=delta+1',
      );
      final bad = await source.capture(
        privateDirectory: x.h.directory,
        mode: AppMode.serverSync,
        deviceId: 'fixture',
        appRevision: 's3-test',
        cancellation: RecoveryCancellation(),
      );
      addTearDown(bad.close);
      expect(
        () => RecoveryReconciliationValidator.validateIncident(
          bad,
          bad.rows('sale_delivery_incidents').single,
        ),
        throwsStateError,
      );
    },
  );
}
