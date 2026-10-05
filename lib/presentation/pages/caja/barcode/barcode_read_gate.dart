/// Compuerta experimental basada en observaciones positivas de cámara.
///
/// El detector no informa frames vacíos en Android/Darwin. Un intervalo sin
/// lecturas puede ser retirada o desenfoque: la validación física queda pendiente
/// para la verificación final y no bloquea integrar Caja (plan, revisión 2).
/// El reloj debe ser monótono (Stopwatch en el lector).
class BarcodeReadGate {
  BarcodeReadGate({
    required Duration Function() clock,
    this.absenceThreshold = const Duration(seconds: 1),
  }) : _clock = clock;

  final Duration Function() _clock;
  final Duration absenceThreshold;
  bool _cameraActive = false;
  bool _needsFreshObservation = true;
  String? _currentCode;
  Duration? _lastSeen;
  bool _consumed = false;

  /// Suspender conserva la presentación consumida. El primer callback nuevo
  /// al reanudar establece otra base temporal; la pausa nunca cuenta como ausencia.
  void setCameraActive(bool active) {
    if (_cameraActive == active) return;
    _cameraActive = active;
    _needsFreshObservation = true;
  }

  /// [codes] contiene identidades normalizadas dentro del área del lector.
  /// Se observa aun con guardado en curso, pero solo se consume al admitir.
  /// Otro código único delimita una nueva presentación (incluido A → B → A).
  /// Una captura ambigua actualiza presencia sin elegir por orden del detector.
  String? observe(Set<String> codes, {bool admissionEnabled = true}) {
    if (!_cameraActive || codes.isEmpty) return null;
    final now = _clock();
    if (_needsFreshObservation) {
      _lastSeen = now;
      _needsFreshObservation = false;
    }
    if (codes.length != 1) {
      if (codes.contains(_currentCode)) _lastSeen = now;
      return null;
    }

    final code = codes.single;
    if (code != _currentCode ||
        (_lastSeen != null && now - _lastSeen! >= absenceThreshold)) {
      _currentCode = code;
      _consumed = false;
    }
    _lastSeen = now;
    if (!admissionEnabled || _consumed) return null;
    // Consumir antes de consultar/seleccionar/guardar: cancelar o fallar no
    // vuelve a abrir el mismo intento en cada frame.
    _consumed = true;
    return code;
  }
}
