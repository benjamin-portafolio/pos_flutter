abstract class SyncEndpointStore {
  Future<String?> readBaseUrl();

  Future<void> saveBaseUrl(String baseUrl);
}
