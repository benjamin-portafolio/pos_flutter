import 'package:drift/drift.dart';

/// Cursor local que indica hasta que secuencia de servidor fue aplicado un pull.
@DataClassName('SyncCheckpoint')
class SyncCheckpoints extends Table {
  TextColumn get checkpointId => text()();

  IntColumn get lastFullPullServerSequence =>
      integer().withDefault(const Constant(0))();

  DateTimeColumn get lastFullPullAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {checkpointId};
}
