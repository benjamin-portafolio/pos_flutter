import 'package:drift/drift.dart';

/// Mixin defining the common synchronization and traceability fields
/// shared across all entity tables in the database.
mixin CommonFields on Table {
  /// Unique global ID generated on the device as a UUID
  TextColumn get id => text()();

  /// Logical deletion flag (active = true means not deleted)
  BoolColumn get active => boolean().withDefault(const Constant(true))();

  /// Version for optimistic concurrency control and conflict resolution
  IntColumn get version => integer().withDefault(const Constant(1))();

  /// Reference to the event that created this record
  TextColumn get createdEventId => text().nullable()();

  /// Reference to the last event that modified this record
  TextColumn get lastEventId => text().nullable()();

  /// Sync cursor representing the official server sequence
  IntColumn get lastServerSequence => integer().nullable()();
}
