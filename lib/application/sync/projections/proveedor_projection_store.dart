import 'proveedor_projection.dart';

abstract interface class ProveedorProjectionStore {
  Future<ProveedorProjection?> findById(String id);
  Future<void> save(ProveedorProjection projection);
  Future<void> deleteCreatedByEvent(String eventId);
  Future<void> advanceServerSequence(String id, int sequence);
  Future<T> atomic<T>(Future<T> Function() action);
}
