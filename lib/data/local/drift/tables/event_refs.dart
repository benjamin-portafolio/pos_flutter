import 'package:drift/drift.dart';

/// Table definition for event references (used in synchronization preflight validation).
class EventRefs extends Table {
  /// Unique global ID generated on the device as a UUID
  TextColumn get eventRefId => text()();

  /// Reference to the related event's event_id
  TextColumn get eventId => text()();

  /// Type of reference (e.g., 'espacio', 'sku', 'user')
  TextColumn get refType => text()();

  /// Identifier of the referenced entity or value
  TextColumn get refId => text()();

  /// Relationship type (e.g., 'affects', 'uses', 'requires_unique')
  TextColumn get relationship => text()();

  /// Sequence assigned by the server upon successful synchronization
  IntColumn get serverSequence => integer().nullable()();

  /// Source classification: 'server' or 'local_pending'
  TextColumn get source => text()();

  @override
  Set<Column> get primaryKey => {eventRefId};
}
