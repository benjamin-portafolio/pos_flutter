import '../../../application/backup/backup_service.dart';
import '../drift/app_database.dart';

class DriftDatabaseStateReader implements DatabaseStateReader {
  DriftDatabaseStateReader({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  @override
  Future<DatabaseState> readState() async {
    final row = await _db
        .customSelect(
          '''
          SELECT
            COUNT(*) AS event_count,
            COALESCE(MAX(local_sequence), 0) AS last_local_sequence
          FROM events
          ''',
          readsFrom: {_db.events},
        )
        .getSingle();

    return DatabaseState(
      eventCount: row.data['event_count'] as int,
      lastLocalSequence: row.data['last_local_sequence'] as int,
    );
  }
}
