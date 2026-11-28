import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_status_store.dart';

void main() {
  test(
    'observa pendientes e incidencias incluso con secuencia remota',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final store = DriftSyncStatusStore(db);
      for (final (id, delivery, application) in [
        ('p', 'pending', 'applied'),
        ('c', 'conflict', 'applied'),
        ('r', 'rejected', 'applied'),
        ('f', 'delivered', 'failed'),
        ('d', 'delivered', 'applied'),
        ('l', 'not_required', 'applied'),
      ]) {
        await db
            .into(db.events)
            .insert(
              EventsCompanion.insert(
                eventId: id,
                aggregateType: 'test',
                aggregateId: id,
                eventType: 'test',
                deviceId: 'device',
                userId: 'user',
                createdAtLocal: DateTime.now(),
                payload: '{}',
                deliveryStatus: Value(delivery),
                applicationStatus: Value(application),
                serverSequence: const Value(1),
              ),
            );
      }
      final initial = await store.watch().first;
      expect(initial.pending, 1);
      expect(
        initial.problems.map((p) => p.eventId),
        unorderedEquals(['c', 'r', 'f']),
      );
      final next = store.watch().firstWhere((s) => s.pending == 0);
      await (db.update(db.events)..where((e) => e.eventId.equals('p'))).write(
        const EventsCompanion(deliveryStatus: Value('delivered')),
      );
      expect((await next).problems.length, 3);
    },
  );
}
