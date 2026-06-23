import 'package:drift/drift.dart';

/// Table definition for the sync events log in SQLite.
@DataClassName('EventRecord')
class Events extends Table {
  /// Unique global ID generated on the device as a UUID
  TextColumn get eventId => text()();

  /// The type of aggregate affected (e.g., 'espacio', 'sale', 'product')
  TextColumn get aggregateType => text()();

  /// The unique ID of the aggregate affected
  TextColumn get aggregateId => text()();

  /// The specific event name/type (e.g., 'espacio_creado', 'producto_creado')
  TextColumn get eventType => text()();

  /// The ID of the device that generated the event
  TextColumn get deviceId => text()();

  /// The ID of the user that performed the action
  TextColumn get userId => text()();

  /// Local sequence order, auto-incremented by the device.
  /// Used as the primary key to ensure strict ordering and auto-increment behavior in SQLite.
  IntColumn get localSequence => integer().autoIncrement()();

  /// Sequence assigned by the server upon successful synchronization
  IntColumn get serverSequence => integer().nullable()();

  /// Cursor sequence known by the device when generating this event
  IntColumn get baseServerSequence => integer().nullable()();

  /// Version of the mutable entity known by the device
  IntColumn get baseVersion => integer().nullable()();

  /// Timestamp of creation on the device
  DateTimeColumn get createdAtLocal => dateTime()();

  /// Timestamp of acceptance on the server
  DateTimeColumn get createdAtServer => dateTime().nullable()();

  /// JSON payload representing event-specific data (serialized as string)
  TextColumn get payload => text()();

  /// Synchronization status: 'pending', 'synced', 'rejected', 'conflict'
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  List<Set<Column>> get uniqueKeys => [
        {eventId}
      ];
}
