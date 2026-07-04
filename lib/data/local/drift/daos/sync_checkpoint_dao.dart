part of '../app_database.dart';

@DriftAccessor(tables: [SyncCheckpoints])
class SyncCheckpointDao extends DatabaseAccessor<AppDatabase>
    with _$SyncCheckpointDaoMixin {
  SyncCheckpointDao(super.db);

  static const fullPullCheckpointId = 'full_pull';

  Future<int> obtenerLastFullPullServerSequence() async {
    final checkpoint =
        await (select(syncCheckpoints)
              ..where((t) => t.checkpointId.equals(fullPullCheckpointId)))
            .getSingleOrNull();

    return checkpoint?.lastFullPullServerSequence ?? 0;
  }

  Future<int> obtenerLastPreflightServerSequence() async {
    final checkpoint =
        await (select(syncCheckpoints)
              ..where((t) => t.checkpointId.equals(fullPullCheckpointId)))
            .getSingleOrNull();

    return checkpoint?.lastPreflightServerSequence ?? 0;
  }

  Future<void> actualizarLastFullPullServerSequence(
    int serverSequence, {
    DateTime? pulledAt,
  }) async {
    final current = await obtenerLastFullPullServerSequence();
    if (serverSequence <= current) return;

    await _ensureFullPullCheckpoint();
    await (update(
      syncCheckpoints,
    )..where((t) => t.checkpointId.equals(fullPullCheckpointId))).write(
      SyncCheckpointsCompanion(
        lastFullPullServerSequence: Value(serverSequence),
        lastFullPullAt: Value(pulledAt ?? DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> actualizarLastPreflightServerSequence(
    int serverSequence, {
    DateTime? preflightAt,
  }) async {
    final current = await obtenerLastPreflightServerSequence();
    if (serverSequence <= current) return;

    await _ensureFullPullCheckpoint();
    await (update(
      syncCheckpoints,
    )..where((t) => t.checkpointId.equals(fullPullCheckpointId))).write(
      SyncCheckpointsCompanion(
        lastPreflightServerSequence: Value(serverSequence),
        lastPreflightAt: Value(preflightAt ?? DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> _ensureFullPullCheckpoint() async {
    await into(syncCheckpoints).insert(
      SyncCheckpointsCompanion.insert(checkpointId: fullPullCheckpointId),
      mode: InsertMode.insertOrIgnore,
    );
  }
}
