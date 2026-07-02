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

  Future<void> actualizarLastFullPullServerSequence(
    int serverSequence, {
    DateTime? pulledAt,
  }) async {
    final current = await obtenerLastFullPullServerSequence();
    if (serverSequence <= current) return;

    await into(syncCheckpoints).insertOnConflictUpdate(
      SyncCheckpointsCompanion.insert(
        checkpointId: fullPullCheckpointId,
        lastFullPullServerSequence: Value(serverSequence),
        lastFullPullAt: Value(pulledAt ?? DateTime.now().toUtc()),
      ),
    );
  }
}
