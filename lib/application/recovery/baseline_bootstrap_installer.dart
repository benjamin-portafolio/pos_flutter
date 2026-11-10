/// Publica una base nueva privada. Nunca sustituye una instalación con datos.
abstract interface class BaselineBootstrapInstaller {
  Future<String> install(
    Map<String, Object?> descriptor,
    Future<List<int>> Function(int index) download,
  );
}
