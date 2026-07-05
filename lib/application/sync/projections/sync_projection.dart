/// Common traceability and synchronization fields for local read projections.
///
/// This is the application-layer counterpart to Drift table common fields.
/// Projection DTOs extend this class so event handlers can depend on sync
/// semantics without importing database table definitions.
abstract class SyncProjection {
  const SyncProjection({
    required this.id,
    required this.active,
    required this.version,
    required this.createdEventId,
    required this.lastEventId,
    required this.lastServerSequence,
  });

  final String id;
  final bool active;
  final int version;
  final String? createdEventId;
  final String? lastEventId;
  final int? lastServerSequence;
}
