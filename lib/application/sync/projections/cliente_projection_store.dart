import 'cliente_projection.dart';

abstract interface class ClienteProjectionStore {
  Future<ClienteProjection?> findById(String id);
  Future<void> insert(ClienteProjection projection);
  Future<void> advanceServerSequence(String id, int serverSequence);
  Future<void> deleteCreatedByEvent(String eventId);
}
