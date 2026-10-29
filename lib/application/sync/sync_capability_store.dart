/// Last observed capabilities per server, local to this installation.
/// A missing record never authorizes offline capture.
abstract class SyncCapabilityStore {
  Future<List<String>?> read(String endpoint);
  Future<void> write(String endpoint, List<String> capabilities);
}
