/// Cliente dedicado; no cambia configuración ni arranca el monitor de sync.
abstract interface class BaselineBootstrapTransport {
  Future<List<int>> descriptor();
  Future<List<int>> chunk(int index);
  Future<Map<String, Object?>> bind(String datasetId, String digest);
}
