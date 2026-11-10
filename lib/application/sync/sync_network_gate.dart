import 'dart:async';

/// Cierra la admisión antes de esperar las respuestas HTTP ya iniciadas.
/// La pausa no cambia modo, endpoint, cursores ni estados de entrega.
class SyncNetworkGate {
  SyncNetworkGate({required bool Function() isServerSync})
    : _isServerSync = isServerSync;

  final bool Function() _isServerSync;
  int _pauses = 0;
  int _active = 0;
  Completer<void>? _idle;
  bool get allowsNetwork => _pauses == 0 && _isServerSync();

  void beginRequest() {
    if (!allowsNetwork) throw StateError('Sincronización de red suspendida.');
    _active++;
  }

  void endRequest() {
    _active--;
    if (_active == 0) {
      _idle?.complete();
      _idle = null;
    }
  }

  Future<void> pause() async {
    _pauses++;
    if (_active > 0) {
      _idle ??= Completer<void>();
      await _idle!.future;
    }
  }

  void resume() {
    if (_pauses == 0) throw StateError('No existe pausa de red.');
    _pauses--;
  }
}
