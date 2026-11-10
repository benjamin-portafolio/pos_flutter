/// Cancelación cooperativa entre filas/archivos. Una captura SQLite en curso
/// termina antes de atenderla; no se interrumpe ni restaura la base de origen.
class RecoveryCancellation {
  bool _cancelled = false;
  void cancel() => _cancelled = true;
  void check() {
    if (_cancelled) throw const RecoveryCancelled();
  }
}

class RecoveryCancelled implements Exception {
  const RecoveryCancelled();
}
