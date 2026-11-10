abstract interface class RecoveryTransport {
  Future<Map<String, Object?>> request(
    String method,
    String path, {
    List<int>? bytes,
    Map<String, String> headers = const {},
  });
  void close();
}
