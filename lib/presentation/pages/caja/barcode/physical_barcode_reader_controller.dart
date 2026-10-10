import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../../../domain/articulos/codigo_barras.dart';
import '../../../../domain/articulos/variante_por_codigo_barras.dart';
import 'physical_barcode_read_admission.dart';
import 'sale_barcode_read_coordinator.dart';
import 'sale_barcode_read_result.dart';

/// Una sesión en memoria. Recibe lecturas completas, nunca teclas o fragmentos.
/// Tras finalizar se crea otro controlador para una nueva sesión; la identidad
/// de esta instancia invalida sus consultas y respuestas de diálogos tardías.
class PhysicalBarcodeReaderController extends ChangeNotifier {
  PhysicalBarcodeReaderController({
    required SaleBarcodeReadCoordinator coordinator,
    required Future<VariantePorCodigoBarras?> Function(
      List<VariantePorCodigoBarras> candidates,
    )
    selectProduct,
    required Future<String?> Function(VariantePorCodigoBarras candidate)
    requestQuantity,
  }) : _coordinator = coordinator,
       _selectProduct = selectProduct,
       _requestQuantity = requestQuantity;

  final SaleBarcodeReadCoordinator _coordinator;
  final Future<VariantePorCodigoBarras?> Function(List<VariantePorCodigoBarras>)
  _selectProduct;
  final Future<String?> Function(VariantePorCodigoBarras) _requestQuantity;
  final _queue = Queue<String>();
  final _done = Completer<void>();
  Completer<void>? _resumeSignal;
  bool _activated = false;
  bool _paused = false;
  bool _dialogOpen = false;
  bool _processing = false;
  bool _hasCurrentRead = false;
  bool _saving = false;
  bool _commandStarted = false;
  bool _finishing = false;
  bool _terminated = false;
  bool _disposed = false;
  bool _releaseScheduled = false;
  Object? _error;
  SaleBarcodeReadResult? _lastResult;

  bool get isAccepting =>
      _activated && !_finishing && !_terminated && !isPaused;
  bool get isPaused => _paused || _dialogOpen || _error != null;
  bool get isProcessing => _processing;
  bool get isSaving => _saving;
  bool get isFinishing => _finishing && !isFinished;
  bool get isFinished => _releaseScheduled;

  /// Excluye la intención en curso, incluso si espera consulta o diálogo.
  int get pendingReadCount => _queue.length;

  /// Incluye la consulta/diálogo actual si todavía no inició su comando.
  /// Es lo que se pierde al confirmar `finish(discardPending: true)`.
  int get unstartedReadCount =>
      _queue.length + (_hasCurrentRead && !_commandStarted ? 1 : 0);
  Object? get error => _error;
  SaleBarcodeReadResult? get lastResult => _lastResult;

  /// Completa al liberar el procesamiento, incluido un comando ya iniciado.
  Future<void> get done => _done.future;

  void activate() {
    if (_activated || _finishing || _terminated) return;
    _activated = true;
    _notify();
  }

  PhysicalBarcodeReadAdmission submit(String input) {
    if (!isAccepting) return PhysicalBarcodeReadAdmission.notAccepting;
    final String? code;
    try {
      code = CodigoBarras.fromInput(input).value;
    } on ArgumentError {
      return PhysicalBarcodeReadAdmission.invalid;
    }
    if (code == null) return PhysicalBarcodeReadAdmission.empty;
    _queue.addLast(code);
    // Cada envío es independiente: no deduplicar por código ni por tiempo.
    _pump();
    _notify();
    return PhysicalBarcodeReadAdmission.accepted;
  }

  /// Congela lo aún no iniciado y los pasos posteriores a una consulta/diálogo.
  /// Un comando atómico en curso termina antes de dejar la cola en pausa.
  void pause() {
    if (_terminated || !_activated || _paused) return;
    _paused = true;
    _notify();
  }

  /// También reconoce un error; continúa solo las otras intenciones aceptadas.
  /// La intención fallida ya salió de la cola y nunca se reintenta aquí.
  void resume() {
    if (_terminated || !_activated || (!_paused && _error == null)) return;
    _paused = false;
    _error = null;
    _wake();
    _pump();
    _notify();
  }

  /// Detiene admisión y drena lo aceptado. Una pausa/error requiere `resume`
  /// explícito; un diálogo pendiente debe resolverse para completar el drenaje.
  /// Con `discardPending`, invalida también la consulta/diálogo que todavía no
  /// inició un comando, descarta la cola y espera cualquier comando en curso.
  Future<void> finish({bool discardPending = false}) {
    if (_terminated || (_finishing && !discardPending)) return done;
    _finishing = true;
    if (discardPending) {
      _terminated = true;
      _queue.clear();
      _wake();
    }
    _pump();
    _completeIfFinished();
    _notify();
    return done;
  }

  Future<void> _waitUntilReady() async {
    while (!_terminated && (_paused || _error != null)) {
      final signal = _resumeSignal ??= Completer<void>();
      await signal.future;
    }
  }

  void _wake() {
    final signal = _resumeSignal;
    _resumeSignal = null;
    signal?.complete();
  }

  Future<T?> _interact<T>(Future<T?> Function() show) async {
    _dialogOpen = true;
    _notify();
    try {
      // Un listener puede pausar o finalizar antes de ceder el foco al diálogo.
      await _waitUntilReady();
      if (_terminated) return null;
      return await show();
    } finally {
      _dialogOpen = false;
      _notify();
    }
  }

  void _pump() {
    if (_processing ||
        !_activated ||
        _terminated ||
        _paused ||
        _error != null) {
      return;
    }
    if (_queue.isEmpty) return;
    _processing = true;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    try {
      while (_queue.isNotEmpty && !_terminated && !_paused && _error == null) {
        final code = _queue.removeFirst();
        _hasCurrentRead = true;
        _lastResult = null;
        _notify();
        try {
          final result = await _coordinator.read(
            code,
            canContinue: () => !_terminated,
            waitUntilReady: _waitUntilReady,
            selectProduct: (candidates) =>
                _interact(() => _selectProduct(candidates)),
            requestQuantity: (candidate) =>
                _interact(() => _requestQuantity(candidate)),
            onSaving: () {
              _saving = true;
              _notify();
            },
            onCommandStarted: () => _commandStarted = true,
          );
          if (!_terminated) _lastResult = result;
        } catch (error) {
          if (!_terminated) _error = error;
        } finally {
          _hasCurrentRead = false;
          _saving = false;
          _commandStarted = false;
          _notify();
        }
      }
    } finally {
      _processing = false;
      _completeIfFinished();
      _notify();
    }
  }

  void _completeIfFinished() {
    if (!_finishing || _processing || _queue.isNotEmpty || _releaseScheduled) {
      return;
    }
    _terminated = true;
    _wake();
    _releaseScheduled = true;
    // Dejar entregar el estado final y salir de cualquier notifyListeners
    // reentrante antes de liberar el notifier. `done` confirma esa liberación.
    scheduleMicrotask(() {
      dispose();
      _done.complete();
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(finish(discardPending: true));
    super.dispose();
  }
}
